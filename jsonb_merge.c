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
 * Compare two JSONB string values using PostgreSQL's JSONB key ordering:
 * first by length, then lexicographically. This matches the sort order that
 * JSONB uses internally for object keys.
 */
static inline int
compare_jsonb_keys(const JsonbValue *a, const JsonbValue *b)
{
    if (a->val.string.len != b->val.string.len)
        return (a->val.string.len > b->val.string.len) ? 1 : -1;
    return memcmp(a->val.string.val, b->val.string.val, a->val.string.len);
}

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
 * Push a merged value for a key that exists in both objects, handling
 * recursive object merge, array concatenation, and scalar replacement.
 */
static void
merge_common_key_value(JsonbValue *val_a, JsonbValue *val_b,
                       bool merge_arrays, JsonbParseState **state)
{
    if (val_a->type == jbvBinary && val_b->type == jbvBinary)
    {
        JsonbContainer *container_a = val_a->val.binary.data;
        JsonbContainer *container_b = val_b->val.binary.data;

        if (JsonContainerIsObject(container_a) && JsonContainerIsObject(container_b))
        {
            /* Recursively merge objects */
            JsonbValue *merged = jsonb_merge_recursive(container_a, container_b, merge_arrays);
            (void) pushJsonbValue(state, WJB_VALUE, merged);
        }
        else if (JsonContainerIsArray(container_a) && JsonContainerIsArray(container_b) && merge_arrays)
        {
            /* Merge arrays if enabled */
            merge_arrays_into_state(container_a, container_b, state);
        }
        else
        {
            /* Different container types or array merge disabled - second value wins */
            (void) pushJsonbValue(state, WJB_VALUE, val_b);
        }
    }
    else
    {
        /* Not both containers - second value wins */
        (void) pushJsonbValue(state, WJB_VALUE, val_b);
    }
}

/*
 * Recursive merge using sorted-key merge.
 *
 * PostgreSQL stores JSONB object keys in sorted order (by length, then
 * lexicographically). We exploit this by iterating both objects simultaneously
 * in a single merge-sort-style pass, achieving O(n + m) complexity instead of
 * the O(m·log n + n·log m) of the lookup-based approach.
 */
static JsonbValue *
jsonb_merge_recursive(JsonbContainer *jca, JsonbContainer *jcb, bool merge_arrays)
{
    JsonbParseState *state = NULL;
    JsonbValue *res;
    JsonbIterator *ita, *itb;
    JsonbIteratorToken toka, tokb;
    JsonbValue key_a, val_a, key_b, val_b;

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

    ita = JsonbIteratorInit(jca);
    itb = JsonbIteratorInit(jcb);

    /* Skip the WJB_BEGIN_OBJECT tokens */
    toka = JsonbIteratorNext(&ita, &key_a, true);
    tokb = JsonbIteratorNext(&itb, &key_b, true);

    /* Read first key from each object */
    toka = JsonbIteratorNext(&ita, &key_a, true);
    tokb = JsonbIteratorNext(&itb, &key_b, true);

    /* Core merge loop: walk both sorted key streams simultaneously */
    while (toka == WJB_KEY && tokb == WJB_KEY)
    {
        int cmp = compare_jsonb_keys(&key_a, &key_b);

        if (cmp < 0)
        {
            /* Key only in A - emit it and advance A */
            toka = JsonbIteratorNext(&ita, &val_a, true);
            (void) pushJsonbValue(&state, WJB_KEY, &key_a);
            (void) pushJsonbValue(&state, WJB_VALUE, &val_a);
            toka = JsonbIteratorNext(&ita, &key_a, true);
        }
        else if (cmp > 0)
        {
            /* Key only in B - emit it and advance B */
            tokb = JsonbIteratorNext(&itb, &val_b, true);
            (void) pushJsonbValue(&state, WJB_KEY, &key_b);
            (void) pushJsonbValue(&state, WJB_VALUE, &val_b);
            tokb = JsonbIteratorNext(&itb, &key_b, true);
        }
        else
        {
            /* Key in both - consume values from both, merge, advance both */
            toka = JsonbIteratorNext(&ita, &val_a, true);
            tokb = JsonbIteratorNext(&itb, &val_b, true);

            (void) pushJsonbValue(&state, WJB_KEY, &key_a);
            merge_common_key_value(&val_a, &val_b, merge_arrays, &state);

            toka = JsonbIteratorNext(&ita, &key_a, true);
            tokb = JsonbIteratorNext(&itb, &key_b, true);
        }
    }

    /* Drain remaining keys from A */
    while (toka == WJB_KEY)
    {
        toka = JsonbIteratorNext(&ita, &val_a, true);
        (void) pushJsonbValue(&state, WJB_KEY, &key_a);
        (void) pushJsonbValue(&state, WJB_VALUE, &val_a);
        toka = JsonbIteratorNext(&ita, &key_a, true);
    }

    /* Drain remaining keys from B */
    while (tokb == WJB_KEY)
    {
        tokb = JsonbIteratorNext(&itb, &val_b, true);
        (void) pushJsonbValue(&state, WJB_KEY, &key_b);
        (void) pushJsonbValue(&state, WJB_VALUE, &val_b);
        tokb = JsonbIteratorNext(&itb, &key_b, true);
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
