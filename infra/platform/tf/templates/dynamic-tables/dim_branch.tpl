SELECT DISTINCT
    cust.value:primary_branch:branch_id::TEXT      AS BRANCH_ID,
    cust.value:primary_branch:branch_name::TEXT    AS BRANCH_NAME,
    cust.value:primary_branch:branch_type::TEXT    AS BRANCH_TYPE,
    cust.value:primary_branch:city::TEXT           AS CITY,
    cust.value:primary_branch:state::TEXT          AS STATE,
    cust.value:primary_branch:region::TEXT         AS REGION,
    cust.value:primary_branch:staff_count::NUMBER  AS STAFF_COUNT,
    cust.value:primary_branch:established::NUMBER  AS ESTABLISHED_YEAR
FROM ${database}.${source_schema}.${table},
     LATERAL FLATTEN(INPUT => JSON_DATA:customers) cust
