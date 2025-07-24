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


/*
 * Recursive merge helper function
 */
static JsonbValue *
jsonb_merge_recursive(JsonbContainer *jca, JsonbContainer *jcb, bool merge_arrays)
{
    JsonbParseState *state = NULL;
    JsonbValue *res;
    JsonbIterator *ita, *itb;
    JsonbIteratorToken typea, typeb;
    JsonbValue va, vb;

    /*
     * We want to iterate through the top-level keys only, and handle nested
     * objects manually.
     */
    bool skipNested = true;

    /* Handle NULL inputs or non-object inputs */
    if (jca == NULL || !JsonContainerIsObject(jca))
    {
        res = palloc(sizeof(JsonbValue));
        res->type = jbvBinary;
        res->val.binary.data = jcb;
        res->val.binary.len = VARSIZE_ANY(jcb);
        return res;
    }
    if (jcb == NULL || !JsonContainerIsObject(jcb))
    {
        res = palloc(sizeof(JsonbValue));
        res->type = jbvBinary;
        res->val.binary.data = jca;
        res->val.binary.len = VARSIZE_ANY(jca);
        return res;
    }

    /* Start building the merged object */
    (void) pushJsonbValue(&state, WJB_BEGIN_OBJECT, NULL);

    /* Iterate through first object */
    ita = JsonbIteratorInit(jca);
    while ((typea = JsonbIteratorNext(&ita, &va, skipNested)) != WJB_DONE)
    {
        if (typea == WJB_KEY)
        {
            JsonbValue key_a = va;
            JsonbValue *val_b;

            /* Get value from first object */
            typea = JsonbIteratorNext(&ita, &va, skipNested);

            /* Look for this key in second object */
            val_b = findJsonbValueFromContainer(jcb, JB_FOBJECT, &key_a);

            /* Push the key */
            (void) pushJsonbValue(&state, WJB_KEY, &key_a);

            if (val_b != NULL)
            {
                /* Key exists in both, check types */
                if (va.type == jbvBinary && val_b->type == jbvBinary)
                {
                    JsonbContainer *ca = va.val.binary.data;
                    JsonbContainer *cb = val_b->val.binary.data;

                    if (JsonContainerIsObject(ca) && JsonContainerIsObject(cb))
                    {
                        /* Both are objects, merge recursively */
                        JsonbValue *merged_val = jsonb_merge_recursive(ca, cb, merge_arrays);
                        (void) pushJsonbValue(&state, WJB_VALUE, merged_val);
                    }
                    else if (JsonContainerIsArray(ca) && JsonContainerIsArray(cb) && merge_arrays)
                    {
                        /* Both are arrays, concatenate them if merge_arrays is true */
                        JsonbIterator *ita_inner, *itb_inner;
                        JsonbIteratorToken tok;
                        JsonbValue v;

                        (void) pushJsonbValue(&state, WJB_BEGIN_ARRAY, NULL);

                        ita_inner = JsonbIteratorInit(ca);
                        while ((tok = JsonbIteratorNext(&ita_inner, &v, true)) != WJB_DONE)
                        {
                            if (tok == WJB_ELEM)
                                (void) pushJsonbValue(&state, tok, &v);
                        }

                        itb_inner = JsonbIteratorInit(cb);
                        while ((tok = JsonbIteratorNext(&itb_inner, &v, true)) != WJB_DONE)
                        {
                            if (tok == WJB_ELEM)
                                (void) pushJsonbValue(&state, tok, &v);
                        }

                        (void) pushJsonbValue(&state, WJB_END_ARRAY, NULL);
                    }
                    else
                    {
                        /* Types are different, or not both objects/arrays, so B overrides A */
                        (void) pushJsonbValue(&state, WJB_VALUE, val_b);
                    }
                }
                else
                {
                    /* Not both binary containers, so B overrides A */
                    (void) pushJsonbValue(&state, WJB_VALUE, val_b);
                }
            }
            else
            {
                /* Key only in first object */
                (void) pushJsonbValue(&state, WJB_VALUE, &va);
            }
        }
    }

    /* Add keys that only exist in second object */
    itb = JsonbIteratorInit(jcb);
    while ((typeb = JsonbIteratorNext(&itb, &vb, skipNested)) != WJB_DONE)
    {
        if (typeb == WJB_KEY)
        {
            JsonbValue key_b = vb;
            JsonbValue *val_a;

            /* Get value from second object */
            typeb = JsonbIteratorNext(&itb, &vb, skipNested);

            /* Check if this key exists in first object */
            val_a = findJsonbValueFromContainer(jca, JB_FOBJECT, &key_b);

            if (val_a == NULL)
            {
                /* Key only exists in second object */
                (void) pushJsonbValue(&state, WJB_KEY, &key_b);
                (void) pushJsonbValue(&state, WJB_VALUE, &vb);
            }
            /* If key exists in both, we already handled it in the first loop */
        }
    }

    /* Finish building the object */
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
