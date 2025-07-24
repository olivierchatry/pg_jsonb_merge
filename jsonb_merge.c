/*
 * jsonb_merge.c
 *    PostgreSQL extension to recursively merge two JSONB values
 */
#include "postgres.h"
#include "fmgr.h"
#include "utils/builtins.h"
#include "utils/jsonb.h"

PG_MODULE_MAGIC;

/* Function declarations */
PG_FUNCTION_INFO_V1(jsonb_merge);
PG_FUNCTION_INFO_V1(jsonb_merge_with_option);

static JsonbValue *jsonb_merge_recursive(JsonbContainer *jca, JsonbContainer *jcb, bool merge_arrays);
static Datum jsonb_merge_worker(PG_FUNCTION_ARGS, bool merge_arrays);
static void merge_arrays_into_state(JsonbContainer *ca, JsonbContainer *cb, JsonbParseState **state);

/*
 * Helper function to merge two arrays into the parse state
 */
static void
merge_arrays_into_state(JsonbContainer *ca, JsonbContainer *cb, JsonbParseState **state)
{
    JsonbIterator *it;
    JsonbIteratorToken tok;
    JsonbValue v;

    (void) pushJsonbValue(state, WJB_BEGIN_ARRAY, NULL);

    /* Add all elements from first array */
    it = JsonbIteratorInit(ca);
    while ((tok = JsonbIteratorNext(&it, &v, true)) != WJB_DONE)
    {
        if (tok == WJB_ELEM)
            (void) pushJsonbValue(state, tok, &v);
    }

    /* Add all elements from second array */
    it = JsonbIteratorInit(cb);
    while ((tok = JsonbIteratorNext(&it, &v, true)) != WJB_DONE)
    {
        if (tok == WJB_ELEM)
            (void) pushJsonbValue(state, tok, &v);
    }

    (void) pushJsonbValue(state, WJB_END_ARRAY, NULL);
}


/*
 * Simplified recursive merge helper function
 */
static JsonbValue *
jsonb_merge_recursive(JsonbContainer *jca, JsonbContainer *jcb, bool merge_arrays)
{
    JsonbParseState *state = NULL;
    JsonbValue *res;
    JsonbIterator *ita, *itb;
    JsonbIteratorToken type_token;
    JsonbValue key_val, val_val;

    /* Early returns for non-object inputs */
    if (jca == NULL || !JsonContainerIsObject(jca))
    {
        if (jcb == NULL)
            return NULL;
        /* Return jcb wrapped in JsonbValue */
        res = palloc(sizeof(JsonbValue));
        res->type = jbvBinary;
        res->val.binary.data = jcb;
        res->val.binary.len = VARSIZE_ANY(jcb);
        return res;
    }
    if (jcb == NULL || !JsonContainerIsObject(jcb))
    {
        /* Return jca wrapped in JsonbValue */
        res = palloc(sizeof(JsonbValue));
        res->type = jbvBinary;
        res->val.binary.data = jca;
        res->val.binary.len = VARSIZE_ANY(jca);
        return res;
    }

    /* Start building the merged object */
    (void) pushJsonbValue(&state, WJB_BEGIN_OBJECT, NULL);

    /* Process all keys from first object */
    ita = JsonbIteratorInit(jca);
    while ((type_token = JsonbIteratorNext(&ita, &key_val, true)) != WJB_DONE)
    {
        if (type_token == WJB_KEY)
        {
            JsonbValue *val_from_b;

            /* Get the corresponding value */
            type_token = JsonbIteratorNext(&ita, &val_val, true);

            /* Look up this key in the second object */
            val_from_b = findJsonbValueFromContainer(jcb, JB_FOBJECT, &key_val);

            /* Add the key to result */
            (void) pushJsonbValue(&state, WJB_KEY, &key_val);

            if (val_from_b != NULL)
            {
                /* Key exists in both objects - decide how to merge */
                if (val_val.type == jbvBinary && val_from_b->type == jbvBinary)
                {
                    JsonbContainer *container_a = val_val.val.binary.data;
                    JsonbContainer *container_b = val_from_b->val.binary.data;

                    if (JsonContainerIsObject(container_a) && JsonContainerIsObject(container_b))
                    {
                        /* Recursively merge objects */
                        JsonbValue *merged = jsonb_merge_recursive(container_a, container_b, merge_arrays);
                        (void) pushJsonbValue(&state, WJB_VALUE, merged);
                    }
                    else if (JsonContainerIsArray(container_a) && JsonContainerIsArray(container_b) && merge_arrays)
                    {
                        /* Merge arrays if enabled */
                        merge_arrays_into_state(container_a, container_b, &state);
                    }
                    else
                    {
                        /* Different container types or array merge disabled - second value wins */
                        (void) pushJsonbValue(&state, WJB_VALUE, val_from_b);
                    }
                }
                else
                {
                    /* Not both containers - second value wins */
                    (void) pushJsonbValue(&state, WJB_VALUE, val_from_b);
                }
            }
            else
            {
                /* Key only exists in first object */
                (void) pushJsonbValue(&state, WJB_VALUE, &val_val);
            }
        }
    }

    /* Add keys that only exist in second object */
    itb = JsonbIteratorInit(jcb);
    while ((type_token = JsonbIteratorNext(&itb, &key_val, true)) != WJB_DONE)
    {
        if (type_token == WJB_KEY)
        {
            JsonbValue *val_from_a;

            /* Get the value */
            type_token = JsonbIteratorNext(&itb, &val_val, true);

            /* Check if this key was already processed (exists in first object) */
            val_from_a = findJsonbValueFromContainer(jca, JB_FOBJECT, &key_val);

            if (val_from_a == NULL)
            {
                /* Key only exists in second object - add it */
                (void) pushJsonbValue(&state, WJB_KEY, &key_val);
                (void) pushJsonbValue(&state, WJB_VALUE, &val_val);
            }
            /* If key exists in both, we already handled it in the first loop */
        }
    }

    /* Complete the object */
    res = pushJsonbValue(&state, WJB_END_OBJECT, NULL);
    return res;
}

/*
 * Main function: jsonb_merge(jsonb, jsonb) -> jsonb
 * Recursively merges two JSONB values, with array merging enabled by default.
 */
Datum
jsonb_merge(PG_FUNCTION_ARGS)
{
    return jsonb_merge_worker(fcinfo, true);
}

/*
 * Main function: jsonb_merge(jsonb, jsonb, boolean) -> jsonb
 * Recursively merges two JSONB values, with optional array merging.
 */
Datum
jsonb_merge_with_option(PG_FUNCTION_ARGS)
{
    bool merge_arrays = PG_GETARG_BOOL(2);
    return jsonb_merge_worker(fcinfo, merge_arrays);
}

/*
 * Common worker function for jsonb_merge variants
 */
static Datum
jsonb_merge_worker(PG_FUNCTION_ARGS, bool merge_arrays)
{
    Jsonb *jba, *jbb;
    Jsonb *result;
    JsonbValue *res_val;

    /* Handle NULL inputs - return the non-NULL input if one is NULL */
    if (PG_ARGISNULL(0))
    {
        if (PG_ARGISNULL(1))
            PG_RETURN_NULL();
        else
            PG_RETURN_JSONB_P(PG_GETARG_JSONB_P(1));
    }
    if (PG_ARGISNULL(1))
        PG_RETURN_JSONB_P(PG_GETARG_JSONB_P(0));

    jba = PG_GETARG_JSONB_P(0);
    jbb = PG_GETARG_JSONB_P(1);

    /* Perform the recursive merge */
    res_val = jsonb_merge_recursive(&jba->root, &jbb->root, merge_arrays);

    result = JsonbValueToJsonb(res_val);

    PG_RETURN_JSONB_P(result);
}
