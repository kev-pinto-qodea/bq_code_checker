-------------------------------------------------------------
-- Script name : kevs_sample_fact.sql
-- Author      : John Doe
-- Date        : 07-07-2025
-- Reason      : Initial - migration to bqsql
-------------------------------------------------------------


BEGIN

--set job variables and update schedule table(s)
--#DECLARE v_job_name      STRING    DEFAULT "fact_withdrawal_feed_service_rule_result";
--#DECLARE v_job_startdttm TIMESTAMP DEFAULT '{startdttm}';  --injected from DAG (utc)
--#DECLARE v_job_enddttm   TIMESTAP  DEFAULT '{enddttm}';    --injected from DAG (utc)
--#DECLARE v_resource      INT64;                            --injected from DAG

-- Set default values
DECLARE v_defnullnum    DEFAULT orgx_cntl.default_vars().defnullnum;
DECLARE v_defnullstr    DEFAULT orgx_cntl.default_vars().defnullstr;
DECLARE v_defhighdttm   DEFAULT orgx_cntl.default_vars().defhighdttm;
DECLARE v_defnulldttm   DEFAULT orgx_cntl.default_vars().defnulldttm;



DECLARE v_mindate TIMESTAMP;
DECLARE v_mindate_int INT64;
DECLARE v_merge_datefilter INT64;
DECLARE v_dim_source_record_set_key INT64 DEFAULT v_defnullnum;
DECLARE v_max_sk INT64;

BEGIN TRANSACTION;

----------------------------------------------------------------------------------
-- update schedule table(s)
--#CALL sched.start_etl_transform(v_job_name , v_job_startdttm , v_job_enddttm , v_resource);
----------------------------------------------------------------------------------

SET v_dim_source_record_set_key=(SELECT COALESCE(source_record_set_key , v_defnullnum) FROM orgx_edw.dim_source_record_set WHERE source_record_set_name = 'Withdrawal Feed Service Rule Result Data');
SET v_max_sk=(SELECT MAX(withdrawal_feed_service_rule_result_key) FROM orgx_edw.fact_withdrawal_feed_service_rule_result);


-- Create final transform table that will be merged into final table
CREATE TEMP TABLE tmp_final_transform_fact_withdrawal_feed_service_rule_result
(
 withdrawal_feed_service_rule_result_key	        INT64	           NOT NULL,
 withdrawal_feed_service_utc_key	                INT64	           NOT NULL,
 withdrawal_feed_service_utc_timestamp	                TIMESTAMP	   NOT NULL,
 withdrawal_ref_key	                                INT64	           NOT NULL,
 withdrawal_feed_service_rule_key	                INT64	           NOT NULL,
 result_desc	                                        STRING	           NOT NULL,
 result_type_flag	                                INT64	           NOT NULL,
 param_1	                                        INT64	           NOT NULL,
 param_2	                                        NUMERIC	           NOT NULL,
 param_3	                                        INT64	           NOT NULL,
 param_4	                                        STRING	           NOT NULL,
 source_record_set_key	                                INT64	           NOT NULL,
 source_key_value_number	                        INT64	           NOT NULL,
);


-------------------------------------------
--
-- MAIN TRANSFROM LOGIC HERE
-- SOURCE DATA FROM STAGE - DAILY INCREMENTAL
-- FULL TABLE DATA ON STAGEHIST
--
------------------------------------------


CREATE TEMP TABLE tmp_transform
AS
SELECT
rrd.DateTimeInserted AS withdrawal_feed_service_utc_timestamp,
w.withdrawal_ref_key AS withdrawal_ref_key,
sr.withdrawal_feed_service_rule_key AS withdrawal_feed_service_rule_key,
res.Result AS result_desc,
res.ResultType AS result_type_flag,
rrd.Param1 AS param_1,
rrd.Param2 AS param_2,
rrd.Param3 AS param_3,
rrd.Param4 AS param_4,
CAST(rrd.sno AS INT64) AS source_key_value_number
FROM edw_stage.stagehist__customerverification_base__withdrawalfeedservice_ruleresultdata_ptn rrd
LEFT OUTER JOIN edw_stage.stagehist__customerverification_base__withdrawalfeedservice_result_ptn res ON rrd.WFFS_Result_sno = res.sno
LEFT OUTER JOIN orgx_edw.dim_withdrawal_ref w ON  res.withdrawalid = w.withdrawal_id
LEFT OUTER JOIN orgx_edw.dim_withdrawal_feed_service_rule sr ON rrd.RuleId = sr.source_key_value_number
;

-- Populate final transform table
INSERT INTO tmp_final_transform_fact_withdrawal_feed_service_rule_result
(
 withdrawal_feed_service_rule_result_key,
 withdrawal_feed_service_utc_key,
 withdrawal_feed_service_utc_timestamp,
 withdrawal_ref_key,
 withdrawal_feed_service_rule_key,
 result_desc,
 result_type_flag,
 param_1,
 param_2,
 param_3,
 param_4,
 source_record_set_key,
 source_key_value_number
)
SELECT
COALESCE(v_max_sk, v_defnullnum)  + ROW_NUMBER() OVER()  AS withdrawal_feed_service_rule_result_key,
COALESCE(orgx_edw.convert_dttm_to_utc_key(DATETIME(s.withdrawal_feed_service_utc_timestamp)), -1) AS withdrawal_feed_service_utc_key,
COALESCE(TIMESTAMP(s.withdrawal_feed_service_utc_timestamp), TIMESTAMP(v_defnulldttm)) AS withdrawal_feed_service_utc_timestamp,
COALESCE(s.withdrawal_ref_key, v_defnullnum) AS withdrawal_ref_key,
COALESCE(s.withdrawal_feed_service_rule_key, v_defnullnum) AS withdrawal_feed_service_rule_key,
COALESCE(s.result_desc, v_defnullstr) AS result_desc,
COALESCE(s.result_type_flag, v_defnullnum) AS result_type_flag,
COALESCE(s.param_1, v_defnullnum) AS param_1,
COALESCE(s.param_2, v_defnullnum) AS param_2,
COALESCE(s.param_3, v_defnullnum) AS param_3,
COALESCE(s.param_4, v_defnullstr) AS param_4,
v_dim_source_record_set_key AS source_record_set_key,
s.source_key_value_number AS source_key_value_number
FROM tmp_transform s

;


-- Merge transform table into final table
MERGE orgx_edw.fact_withdrawal_feed_service_rule_result t
USING tmp_final_transform_fact_withdrawal_feed_service_rule_result s
   ON  t.source_key_value_number                  = s.source_key_value_number
   AND t.withdrawal_feed_service_rule_result_key  = s.withdrawal_feed_service_rule_result_key
   AND t.withdrawal_feed_service_utc_timestamp    = s.withdrawal_feed_service_utc_timestamp
WHEN NOT MATCHED BY TARGET
THEN INSERT
(
 withdrawal_feed_service_rule_result_key,
 withdrawal_feed_service_utc_key,
 withdrawal_feed_service_utc_timestamp,
 withdrawal_ref_key,
 withdrawal_feed_service_rule_key,
 result_desc,
 result_type_flag,
 param_1,
 param_2,
 param_3,
 param_4,
 source_record_set_key,
 source_key_value_number,
 last_mod_utc_timestamp,
 up_to_dateness_utc_hwm_datetime
)
VALUES
(
 s.withdrawal_feed_service_rule_result_key,
 s.withdrawal_feed_service_utc_key,
 s.withdrawal_feed_service_utc_timestamp,
 s.withdrawal_ref_key,
 s.withdrawal_feed_service_rule_key,
 s.result_desc,
 s.result_type_flag,
 s.param_1,
 s.param_2,
 s.param_3,
 s.param_4,
 s.source_record_set_key,
 s.source_key_value_number,
 CURRENT_TIMESTAMP(),
 DATETIME(v_defhighdttm)
)
WHEN MATCHED AND
(
   t.withdrawal_feed_service_utc_key                    IS DISTINCT FROM s.withdrawal_feed_service_utc_key
OR t.withdrawal_ref_key                                 IS DISTINCT FROM s.withdrawal_ref_key
OR t.withdrawal_feed_service_rule_key                   IS DISTINCT FROM s.withdrawal_feed_service_rule_key
OR t.result_desc                                        IS DISTINCT FROM s.result_desc
OR t.result_type_flag                                   IS DISTINCT FROM s.result_type_flag
OR t.param_1                                            IS DISTINCT FROM s.param_1
OR t.param_2                                            IS DISTINCT FROM s.param_2
OR t.param_3                                            IS DISTINCT FROM s.param_3
OR t.param_4                                            IS DISTINCT FROM s.param_4
OR t.source_record_set_key                              IS DISTINCT FROM s.source_record_set_key

)
THEN UPDATE SET
  withdrawal_feed_service_utc_key                    = s.withdrawal_feed_service_utc_key
, withdrawal_ref_key                                 = s.withdrawal_ref_key
, withdrawal_feed_service_rule_key                   = s.withdrawal_feed_service_rule_key
, result_desc                                        = s.result_desc
, result_type_flag                                   = s.result_type_flag
, param_1                                            = s.param_1
, param_2                                            = s.param_2
, param_3                                            = s.param_3
, param_4                                            = s.param_4
, source_record_set_key                              = s.source_record_set_key
, last_mod_utc_timestamp                             = CURRENT_TIMESTAMP()
, up_to_dateness_utc_hwm_datetime                    = DATETIME(v_defhighdttm)
;


---------------------------------------------------------------------------------
-- update schedule table(s)
--#CALL sched.end_etl_transform(v_job_name , v_job_startdttm , v_job_enddttm , v_resource);
----------------------------------------------------------------------------------
COMMIT TRANSACTION;

EXCEPTION WHEN ERROR THEN
--#  CALL sched.error_etl_transform(v_job_name , v_job_startdttm , v_job_enddttm, v_resource , @@error.message);
 ROLLBACK TRANSACTION;
 RAISE;

-- Drop temp tables
DROP TABLE tmp_final_transform_fact_withdrawal_feed_service_rule_result;
END;
