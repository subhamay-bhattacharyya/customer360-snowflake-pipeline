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
        COALESCE(
            TRY_TO_TIMESTAMP_NTZ(TRY_TO_DATE(t.$1:extract_date::STRING)),
            TRY_TO_TIMESTAMP_NTZ(t.$1:extract_date::STRING, 'YYYY-MM-DD HH24:MI:SS'),
            TRY_TO_TIMESTAMP_NTZ(t.$1:extract_date::STRING, 'YYYY-MM-DD"T"HH24:MI:SS'),
            TRY_TO_TIMESTAMP_NTZ(t.$1:extract_date::STRING, 'DD-MM-YYYY HH24:MI:SS')
        )                                                AS INDEX_RECORD_TS,
        t.$1::VARIANT                                    AS JSON_DATA,
        TRY_TO_NUMBER(t.$1:record_count::STRING)         AS RECORD_COUNT,
        t.$1:schema_version::VARCHAR                     AS JSON_VERSION,
        METADATA$FILENAME                                AS _STG_FILE_NAME,
        METADATA$FILE_LAST_MODIFIED                      AS _STG_FILE_LOAD_TS,
        METADATA$FILE_CONTENT_KEY                        AS _STG_FILE_MD5,
        CURRENT_TIMESTAMP()                              AS _COPY_DATA_TS
    FROM @${database}.${schema}.${stage} t
)
FILE_FORMAT = (FORMAT_NAME = '${database}.${schema}.${file_format}')
ON_ERROR = 'CONTINUE'
