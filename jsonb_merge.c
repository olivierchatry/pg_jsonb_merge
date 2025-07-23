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
static JsonbValue *jsonb_merge_recursive(JsonbContainer *jca, JsonbContainer *jcb);

/*
 * Recursive merge helper function
 */
static JsonbValue *
jsonb_merge_recursive(JsonbContainer *jca, JsonbContainer *jcb)
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
                /* Key exists in both */
                if (va.type == jbvBinary && val_b->type == jbvBinary &&
                    JsonContainerIsObject(va.val.binary.data) &&
                    JsonContainerIsObject(val_b->val.binary.data))
                {
                    /* Both values are objects, recursively merge them */
                    JsonbValue *merged_val = jsonb_merge_recursive(va.val.binary.data, val_b->val.binary.data);
                    (void) pushJsonbValue(&state, WJB_VALUE, merged_val);
                }
                else
                {
                    /* At least one is not an object - use value from second object */
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
 * Recursively merges two JSONB values
 */
Datum
jsonb_merge(PG_FUNCTION_ARGS)
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
    res_val = jsonb_merge_recursive(&jba->root, &jbb->root);

    result = JsonbValueToJsonb(res_val);

    PG_RETURN_JSONB_P(result);
}
