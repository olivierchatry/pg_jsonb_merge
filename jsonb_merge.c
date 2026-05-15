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
PG_FUNCTION_INFO_V1(jsonb_merge_with_key);

static JsonbValue *jsonb_merge_recursive(JsonbContainer *jca, JsonbContainer *jcb, bool merge_arrays, const char *array_merge_key, int array_merge_key_len);
static Datum jsonb_merge_worker(PG_FUNCTION_ARGS, bool merge_arrays, const char *array_merge_key, int array_merge_key_len);
static void merge_arrays_into_state(JsonbContainer *ca, JsonbContainer *cb, JsonbParseState **state);
static bool jsonb_scalar_eq(const JsonbValue *a, const JsonbValue *b);
static void merge_arrays_by_key(JsonbContainer *ca, JsonbContainer *cb, const char *array_merge_key, int array_merge_key_len, bool merge_arrays, JsonbParseState **state);

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
 * Compare two scalar JsonbValues for equality.
 * Returns true if both values are of the same scalar type and equal.
 * Non-scalar types (objects, arrays) always return false.
 */
static bool
jsonb_scalar_eq(const JsonbValue *a, const JsonbValue *b)
{
    if (a->type != b->type)
        return false;

    switch (a->type)
    {
        case jbvNull:
            return true;
        case jbvBool:
            return a->val.boolean == b->val.boolean;
        case jbvNumeric:
            return DatumGetInt32(DirectFunctionCall2(numeric_cmp,
                                 PointerGetDatum(a->val.numeric),
                                 PointerGetDatum(b->val.numeric))) == 0;
        case jbvString:
            return (a->val.string.len == b->val.string.len &&
                    memcmp(a->val.string.val, b->val.string.val, a->val.string.len) == 0);
        default:
            return false;
    }
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
 * Merge two arrays of objects by matching on a specified key.
 *
 * For each element in array A that is an object containing the merge key
 * with a scalar value, we look for a matching element in array B. Matched
 * pairs are recursively deep-merged. Unmatched elements from A are kept,
 * and unmatched elements from B are appended.
 *
 * Elements that are not objects, or objects lacking the merge key, or
 * objects whose merge key value is non-scalar, are never matched and are
 * kept/appended as-is.
 */
static void
merge_arrays_by_key(JsonbContainer *ca, JsonbContainer *cb,
                    const char *array_merge_key, int array_merge_key_len,
                    bool merge_arrays, JsonbParseState **state)
{
    JsonbIterator *it;
    JsonbIteratorToken tok;
    JsonbValue v;
    JsonbValue search_key;
    int idx, i, j;

    int count_a = JsonContainerSize(ca);
    int count_b = JsonContainerSize(cb);

    /* Collect elements and extract key values from array A */
    JsonbValue *elems_a = palloc(count_a * sizeof(JsonbValue));
    JsonbValue *keys_a = palloc(count_a * sizeof(JsonbValue));
    bool *has_key_a = palloc0(count_a * sizeof(bool));
    bool *merged_a = palloc0(count_a * sizeof(bool));

    search_key.type = jbvString;
    search_key.val.string.val = array_merge_key;
    search_key.val.string.len = array_merge_key_len;

    idx = 0;
    it = JsonbIteratorInit(ca);
    while ((tok = JsonbIteratorNext(&it, &v, true)) != WJB_DONE)
    {
        if (tok == WJB_ELEM)
        {
            elems_a[idx] = v;
            if (v.type == jbvBinary && JsonContainerIsObject(v.val.binary.data))
            {
                JsonbValue *found = findJsonbValueFromContainer(v.val.binary.data,
                                                                JB_FOBJECT, &search_key);
                if (found != NULL && found->type != jbvBinary)
                {
                    keys_a[idx] = *found;
                    has_key_a[idx] = true;
                }
            }
            idx++;
        }
    }

    /* Collect elements and extract key values from array B */
    JsonbValue *elems_b = palloc(count_b * sizeof(JsonbValue));
    JsonbValue *keys_b = palloc(count_b * sizeof(JsonbValue));
    bool *has_key_b = palloc0(count_b * sizeof(bool));
    bool *used_b = palloc0(count_b * sizeof(bool));

    idx = 0;
    it = JsonbIteratorInit(cb);
    while ((tok = JsonbIteratorNext(&it, &v, true)) != WJB_DONE)
    {
        if (tok == WJB_ELEM)
        {
            elems_b[idx] = v;
            if (v.type == jbvBinary && JsonContainerIsObject(v.val.binary.data))
            {
                JsonbValue *found = findJsonbValueFromContainer(v.val.binary.data,
                                                                JB_FOBJECT, &search_key);
                if (found != NULL && found->type != jbvBinary)
                {
                    keys_b[idx] = *found;
                    has_key_b[idx] = true;
                }
            }
            idx++;
        }
    }

    /* Build the merged array */
    (void) pushJsonbValue(state, WJB_BEGIN_ARRAY, NULL);

    /* Emit A elements, merging with matched B elements */
    for (i = 0; i < count_a; i++)
    {
        if (has_key_a[i])
        {
            for (j = 0; j < count_b; j++)
            {
                if (!used_b[j] && has_key_b[j] &&
                    jsonb_scalar_eq(&keys_a[i], &keys_b[j]))
                {
                    /* Match found - deep merge the two objects */
                    JsonbValue *m = jsonb_merge_recursive(
                        elems_a[i].val.binary.data,
                        elems_b[j].val.binary.data,
                        merge_arrays, array_merge_key, array_merge_key_len);
                    (void) pushJsonbValue(state, WJB_ELEM, m);
                    used_b[j] = true;
                    merged_a[i] = true;
                    break;
                }
            }
        }

        if (!merged_a[i])
            (void) pushJsonbValue(state, WJB_ELEM, &elems_a[i]);
    }

    /* Append unmatched B elements */
    for (j = 0; j < count_b; j++)
    {
        if (!used_b[j])
            (void) pushJsonbValue(state, WJB_ELEM, &elems_b[j]);
    }

    (void) pushJsonbValue(state, WJB_END_ARRAY, NULL);

    pfree(elems_a);
    pfree(keys_a);
    pfree(has_key_a);
    pfree(merged_a);
    pfree(elems_b);
    pfree(keys_b);
    pfree(has_key_b);
    pfree(used_b);
}

/*
 * Push a merged value for a key that exists in both objects, handling
 * recursive object merge, array concatenation, and scalar replacement.
 */
static void
merge_common_key_value(JsonbValue *val_a, JsonbValue *val_b,
                       bool merge_arrays, const char *array_merge_key,
                       int array_merge_key_len, JsonbParseState **state)
{
    if (val_a->type == jbvBinary && val_b->type == jbvBinary)
    {
        JsonbContainer *container_a = val_a->val.binary.data;
        JsonbContainer *container_b = val_b->val.binary.data;

        if (JsonContainerIsObject(container_a) && JsonContainerIsObject(container_b))
        {
            /* Recursively merge objects */
            JsonbValue *merged = jsonb_merge_recursive(container_a, container_b,
                                                       merge_arrays, array_merge_key,
                                                       array_merge_key_len);
            (void) pushJsonbValue(state, WJB_VALUE, merged);
        }
        else if (JsonContainerIsArray(container_a) && JsonContainerIsArray(container_b) && merge_arrays)
        {
            if (array_merge_key != NULL)
            {
                /* Merge arrays by matching on the specified key */
                merge_arrays_by_key(container_a, container_b,
                                    array_merge_key, array_merge_key_len,
                                    merge_arrays, state);
            }
            else
            {
                /* Simple array concatenation */
                merge_arrays_into_state(container_a, container_b, state);
            }
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
jsonb_merge_recursive(JsonbContainer *jca, JsonbContainer *jcb, bool merge_arrays,
                      const char *array_merge_key, int array_merge_key_len)
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
            merge_common_key_value(&val_a, &val_b, merge_arrays,
                                   array_merge_key, array_merge_key_len, &state);

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
    return jsonb_merge_worker(fcinfo, true, NULL, 0);
}

/*
 * Main function: jsonb_merge(jsonb, jsonb, boolean) -> jsonb
 * Recursively merges two JSONB values, with optional array merging.
 */
Datum
jsonb_merge_with_option(PG_FUNCTION_ARGS)
{
    bool merge_arrays = PG_GETARG_BOOL(2);
    return jsonb_merge_worker(fcinfo, merge_arrays, NULL, 0);
}

/*
 * Main function: jsonb_merge(jsonb, jsonb, boolean, text) -> jsonb
 * Recursively merges two JSONB values, with optional array merging
 * and key-based array-of-objects matching.
 */
Datum
jsonb_merge_with_key(PG_FUNCTION_ARGS)
{
    bool merge_arrays = PG_GETARG_BOOL(2);
    const char *key = NULL;
    int key_len = 0;

    if (!PG_ARGISNULL(3))
    {
        text *key_text = PG_GETARG_TEXT_PP(3);
        key = VARDATA_ANY(key_text);
        key_len = VARSIZE_ANY_EXHDR(key_text);
    }

    return jsonb_merge_worker(fcinfo, merge_arrays, key, key_len);
}

/*
 * Common worker function for jsonb_merge variants
 */
static Datum
jsonb_merge_worker(PG_FUNCTION_ARGS, bool merge_arrays,
                   const char *array_merge_key, int array_merge_key_len)
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
    res_val = jsonb_merge_recursive(&jba->root, &jbb->root, merge_arrays,
                                    array_merge_key, array_merge_key_len);

    result = JsonbValueToJsonb(res_val);

    PG_RETURN_JSONB_P(result);
}
