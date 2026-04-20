COPY INTO ${database}.${schema}.${table} (
    INDEX_RECORD_TS,
    JSON_DATA,
    RECORD_COUNT,
    JSON_VERSION,
    _STG_FILE_NAME,
    _STG_FILE_LOAD_TS,
    _STG_FILE_MD5,
    _COPY_DATA_TS
)
FROM (
    SELECT
        METADATA$FILE_LAST_MODIFIED::TIMESTAMP_NTZ  AS INDEX_RECORD_TS,
        t.$1::VARIANT                                AS JSON_DATA,
        ARRAY_SIZE(t.$1:customers)                   AS RECORD_COUNT,
        'northbridge-v3.0'                           AS JSON_VERSION,
        METADATA$FILENAME                            AS _STG_FILE_NAME,
        METADATA$FILE_LAST_MODIFIED                  AS _STG_FILE_LOAD_TS,
        METADATA$FILE_CONTENT_KEY                    AS _STG_FILE_MD5,
        CURRENT_TIMESTAMP()                          AS _COPY_DATA_TS
    FROM @${database}.${schema}.${stage} t
)
FILE_FORMAT = (FORMAT_NAME = '${database}.${schema}.${file_format}')
ON_ERROR    = 'CONTINUE'
