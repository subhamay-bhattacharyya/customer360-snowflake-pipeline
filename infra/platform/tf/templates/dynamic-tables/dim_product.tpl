SELECT DISTINCT
    acct.value:product_id::TEXT        AS PRODUCT_ID,
    acct.value:product_name::TEXT      AS PRODUCT_NAME,
    acct.value:product_type::TEXT      AS PRODUCT_TYPE,
    acct.value:product_category::TEXT  AS PRODUCT_CATEGORY
FROM ${database}.${source_schema}.${table},
     LATERAL FLATTEN(INPUT => JSON_DATA:customers) cust,
     LATERAL FLATTEN(INPUT => cust.value:accounts) acct
