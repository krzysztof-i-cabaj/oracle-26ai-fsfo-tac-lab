-- ==============================================================================
-- Tytul:        tac_full_readiness_26ai.sql
-- Opis:         26ai-specific variant tac_full_readiness.sql.
--               Patch sekcja 11: GV$REPLAY_STAT_SUMMARY zostal usuniety w 23ai/26ai
--               -> agregacja per-instance z GV$REPLAY_CONTEXT (per-context view
--               z polami SEQUENCE/SYSDATE/SYSGUID/LOBS _CAPTURED/_REPLAYED).
--               Reszta sekcji 1-10, 12 identyczna z oryginalem (FIX-082).
-- Description [EN]: 26ai-specific variant. Section 11 patched: GV$REPLAY_STAT_SUMMARY
--               removed in 23ai/26ai -> aggregation from GV$REPLAY_CONTEXT.
--
-- Autor:        KCB Kris
-- Data:         2026-04-27
-- Wersja:       1.0 (FIX-082, baza: oryginal tac_full_readiness.sql v1.0)
--
-- UWAGA: NIE modyfikuj oryginalu tac_full_readiness.sql - jest reusable dla 19c/21c.
--        Dla 23ai/26ai uzywaj _26ai variant. deploy_tac_service.sh v1.3+ preferuje
--        _26ai z fallback do oryginalu.
--
-- Wymagania [PL]:    - Oracle 19c+ EE
--                    - Rola SELECT_CATALOG_ROLE
--                    - Uruchomic na PRIM (i opcjonalnie na STBY po switchover)
-- Requirements [EN]: - Oracle 19c+ EE
--                    - SELECT_CATALOG_ROLE
--                    - Run on PRIM (and optionally STBY after switchover)
--
-- Uzycie [PL]:       sqlconn.sh -s PRIM -f sql/tac_full_readiness.sql -o reports/PRIM_tac_readiness.txt
-- Usage [EN]:        sqlconn.sh -s PRIM -f sql/tac_full_readiness.sql -o reports/PRIM_tac_readiness.txt
-- ==============================================================================

SET PAGESIZE 200
SET LINESIZE 220
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON

PROMPT ================================================================================
PROMPT    TAC Full Readiness Check (12 sections)
PROMPT ================================================================================
PROMPT

COLUMN sprawdzenie   FORMAT A48 HEADING "Sprawdzenie / Check"
COLUMN wartosc       FORMAT A40 HEADING "Wartosc / Value"
COLUMN oczekiwane    FORMAT A25 HEADING "Oczekiwane / Expected"
COLUMN status        FORMAT A8  HEADING "Status"

-- ============================================================================
-- SEKCJA 1: Wersja i edycja / Section 1: Version and Edition
-- ============================================================================

PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 1 / SECTION 1: Wersja i edycja / Version and Edition
PROMPT --------------------------------------------------------------------------------

WITH ver AS (SELECT banner_full AS bf FROM v$version WHERE banner_full LIKE '%Database%')
SELECT 'Oracle version (wymagane 23ai+)'              AS sprawdzenie,
       SUBSTR(bf, 1, 40)                             AS wartosc,
       '23ai / 26ai'                     AS oczekiwane,
       CASE WHEN bf LIKE '%23.%' OR bf LIKE '%26.%'
            THEN 'PASS' ELSE 'FAIL' END              AS status
FROM ver
UNION ALL
SELECT 'Enterprise Edition',
       (SELECT banner FROM v$version WHERE banner LIKE '%Edition%' FETCH FIRST 1 ROWS ONLY),
       'Enterprise Edition',
       CASE WHEN EXISTS (SELECT 1 FROM v$version WHERE banner LIKE '%Enterprise%')
            THEN 'PASS' ELSE 'FAIL' END
FROM dual;

-- ============================================================================
-- SEKCJA 2: Podstawy DG / Section 2: DG basics
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 2 / SECTION 2: Podstawy Data Guard / Data Guard basics
PROMPT --------------------------------------------------------------------------------

SELECT 'Database role'                               AS sprawdzenie,
       database_role                                 AS wartosc,
       'PRIMARY lub PHYSICAL STANDBY'                AS oczekiwane,
       CASE WHEN database_role IN ('PRIMARY','PHYSICAL STANDBY')
            THEN 'PASS' ELSE 'WARN' END              AS status
FROM v$database
UNION ALL
SELECT 'Force logging (wymagane dla DG + TAC)',
       force_logging,
       'YES',
       CASE WHEN force_logging = 'YES' THEN 'PASS' ELSE 'FAIL' END
FROM v$database
UNION ALL
SELECT 'Archivelog mode',
       log_mode,
       'ARCHIVELOG',
       CASE WHEN log_mode = 'ARCHIVELOG' THEN 'PASS' ELSE 'FAIL' END
FROM v$database
UNION ALL
SELECT 'Flashback on (dla auto reinstate po failover)',
       flashback_on,
       'YES',
       CASE WHEN flashback_on = 'YES' THEN 'PASS' ELSE 'WARN' END
FROM v$database;

-- ============================================================================
-- SEKCJA 3: Transaction Guard (DBMS_APP_CONT) / Section 3: Transaction Guard
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 3 / SECTION 3: Transaction Guard (DBMS_APP_CONT)
PROMPT --------------------------------------------------------------------------------

SELECT 'Pakiet DBMS_APP_CONT istnieje i jest VALID'  AS sprawdzenie,
       NVL((SELECT status FROM dba_objects
            WHERE object_name = 'DBMS_APP_CONT'
              AND object_type = 'PACKAGE'), 'BRAK') AS wartosc,
       'VALID'                                      AS oczekiwane,
       CASE WHEN EXISTS (SELECT 1 FROM dba_objects
                         WHERE object_name = 'DBMS_APP_CONT'
                           AND object_type = 'PACKAGE'
                           AND status = 'VALID')
            THEN 'PASS' ELSE 'FAIL' END             AS status
FROM dual
UNION ALL
SELECT 'Package body DBMS_APP_CONT VALID',
       NVL((SELECT status FROM dba_objects
            WHERE object_name = 'DBMS_APP_CONT'
              AND object_type = 'PACKAGE BODY'), 'BRAK'),
       'VALID',
       CASE WHEN EXISTS (SELECT 1 FROM dba_objects
                         WHERE object_name = 'DBMS_APP_CONT'
                           AND object_type = 'PACKAGE BODY'
                           AND status = 'VALID')
            THEN 'PASS' ELSE 'FAIL' END
FROM dual;

-- Rozmiar tabeli LTXID (retencja commit outcomes)
COLUMN segment_name FORMAT A40 HEADING "Segment"
COLUMN mb           FORMAT 99999.99 HEADING "MB"
COLUMN tablespace   FORMAT A20 HEADING "Tablespace"

PROMPT
PROMPT Tabele LTXID (Transaction Guard commit outcomes):
SELECT segment_name,
       ROUND(bytes/1024/1024, 2)   AS mb,
       tablespace_name             AS tablespace
FROM   dba_segments
WHERE  segment_name LIKE '%LTXID%'
  OR   segment_name LIKE '%TRANS$%'
ORDER  BY bytes DESC
FETCH  FIRST 10 ROWS ONLY;

-- ============================================================================
-- SEKCJA 4: Services aplikacyjne / Section 4: Application services
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 4 / SECTION 4: Services aplikacyjne / Application services
PROMPT --------------------------------------------------------------------------------

COLUMN service_name               FORMAT A25 HEADING "Service"
COLUMN failover_type              FORMAT A12 HEADING "Failover type"
COLUMN failover_restore           FORMAT A8  HEADING "Restore"
COLUMN commit_outcome             FORMAT A6  HEADING "Commit"
COLUMN retention_timeout          FORMAT 99999 HEADING "Retention"
COLUMN replay_init_time_num       FORMAT 99999 HEADING "ReplayTmout"
COLUMN session_state_consistency  FORMAT A10 HEADING "SessionSt"
COLUMN drain_timeout              FORMAT 9999 HEADING "Drain"
COLUMN aq_ha_notifications        FORMAT A4  HEADING "FAN"
COLUMN clb_goal                   FORMAT A8  HEADING "CLB_goal"

-- F-02: kolumna failover_restore (LEVEL1/AUTO/NONE) jest obowiazkowa dla TAC w 26ai.
-- F-02: failover_restore column (LEVEL1/AUTO/NONE) is mandatory for TAC in 26ai.
SELECT name                       AS service_name,
       failover_type,
       failover_restore,
       commit_outcome,
       retention_timeout,
       replay_initiation_timeout  AS replay_init_time_num,
       session_state_consistency,
       drain_timeout,
       aq_ha_notifications,
       clb_goal
FROM   dba_services
WHERE  name NOT LIKE 'SYS%'
  AND  name NOT LIKE '%XDB%'
  AND  name NOT LIKE '%CDB%'
ORDER  BY name;

-- ============================================================================
-- SEKCJA 5: TAC services - walidacja atrybutow / Section 5: TAC service attributes
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 5 / SECTION 5: TAC services - walidacja atrybutow
PROMPT --------------------------------------------------------------------------------

-- Sprawdza tylko te services, ktore MAJA failover_type=TRANSACTION (kandydaty na TAC)
WITH tac_candidates AS (
    SELECT name,
           failover_type,
           failover_restore,
           commit_outcome,
           retention_timeout,
           replay_initiation_timeout,
           session_state_consistency,
           drain_timeout,
           aq_ha_notifications
    FROM   dba_services
    WHERE  failover_type = 'TRANSACTION'
)
SELECT
    name || ' - ' || kryterium        AS sprawdzenie,
    aktualna                          AS wartosc,
    oczekiwana                        AS oczekiwane,
    status
FROM (
    SELECT name,
           'failover_type=TRANSACTION'                     AS kryterium,
           failover_type                                   AS aktualna,
           'TRANSACTION'                                   AS oczekiwana,
           CASE WHEN failover_type = 'TRANSACTION' THEN 'PASS' ELSE 'FAIL' END AS status,
           1 AS ord
    FROM   tac_candidates
    UNION ALL
    SELECT name,
           'commit_outcome=TRUE',
           commit_outcome,
           'TRUE',
           CASE WHEN commit_outcome = 'YES' THEN 'PASS' ELSE 'FAIL' END,
           2
    FROM   tac_candidates
    UNION ALL
    SELECT name,
           'retention_timeout (86400 reco.)',
           TO_CHAR(retention_timeout),
           '>= 86400 s (24h)',
           CASE WHEN retention_timeout >= 86400 THEN 'PASS'
                WHEN retention_timeout > 0      THEN 'WARN'
                ELSE 'FAIL' END,
           3
    FROM   tac_candidates
    UNION ALL
    SELECT name,
           'session_state_consistency=DYNAMIC',
           session_state_consistency,
           'DYNAMIC',
           CASE WHEN session_state_consistency = 'DYNAMIC' THEN 'PASS' ELSE 'WARN' END,
           4
    FROM   tac_candidates
    UNION ALL
    SELECT name,
           'drain_timeout (300 reco.)',
           TO_CHAR(drain_timeout),
           '>= 60 s (300 reco.)',
           CASE WHEN drain_timeout >= 60 THEN 'PASS' ELSE 'WARN' END,
           5
    FROM   tac_candidates
    UNION ALL
    SELECT name,
           'aq_ha_notifications (FAN)',
           aq_ha_notifications,
           'TRUE',
           CASE WHEN aq_ha_notifications = 'YES' THEN 'PASS' ELSE 'FAIL' END,
           6
    FROM   tac_candidates
    UNION ALL
    SELECT name,
           'replay_initiation_timeout (900 reco.)',
           TO_CHAR(replay_initiation_timeout),
           '>= 300 s (900 reco.)',
           CASE WHEN replay_initiation_timeout >= 300 THEN 'PASS' ELSE 'WARN' END,
           7
    FROM   tac_candidates
    UNION ALL
    -- F-02: failover_restore=LEVEL1 to wymog TAC w 26ai. Bez tej flagi
    --       replay sesji jest odrzucany przez AppCont, mimo poprawnych
    --       pozostalych atrybutow. Jedyne dopuszczalne wartosci: LEVEL1 (PASS),
    --       AUTO (WARN, dziala ale wybor restore mode jest implicit).
    -- F-02: failover_restore=LEVEL1 is mandatory for TAC in 26ai. Without it
    --       AppCont rejects session replay even if other attributes are correct.
    SELECT name,
           'failover_restore=LEVEL1',
           NVL(failover_restore, 'NULL'),
           'LEVEL1',
           CASE WHEN failover_restore = 'LEVEL1' THEN 'PASS'
                WHEN failover_restore = 'AUTO'   THEN 'WARN'
                ELSE 'FAIL' END,
           8
    FROM   tac_candidates
)
ORDER BY name, ord;

-- Czy w ogole sa jakies TAC services?
SELECT
    'Liczba TAC services (failover_type=TRANSACTION)' AS sprawdzenie,
    TO_CHAR(COUNT(*))                                AS wartosc,
    '>= 1'                                           AS oczekiwane,
    CASE WHEN COUNT(*) >= 1 THEN 'PASS' ELSE 'FAIL' END AS status
FROM   dba_services
WHERE  failover_type = 'TRANSACTION';

-- ============================================================================
-- SEKCJA 6: Role-based services (dla DG switchover) / Section 6: Role-based
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 6 / SECTION 6: Role-based services (dla auto-switchover)
PROMPT --------------------------------------------------------------------------------

-- DBA_SERVICES pokazuje konfigurację ale nie "role"; sprawdzamy czy service
-- jest started na obecnej roli (GV$SERVICES)
COLUMN inst_id        FORMAT 999 HEADING "Inst"
COLUMN service_name   FORMAT A25 HEADING "Service"
COLUMN network_name   FORMAT A25 HEADING "Network name"
COLUMN failover_type2 FORMAT A14 HEADING "Failover type"

SELECT gs.inst_id,
       gs.name                AS service_name,
       gs.network_name,
       gs.failover_type       AS failover_type2,
       CASE WHEN gs.failover_type = 'TRANSACTION' THEN 'TAC' ELSE '-' END AS info
FROM   gv$services gs
WHERE  gs.name NOT LIKE 'SYS%'
  AND  gs.name NOT LIKE '%XDB%'
  AND  gs.name NOT LIKE '%CDB%'
ORDER  BY gs.inst_id, gs.name;

-- ============================================================================
-- SEKCJA 7: FAN/ONS - parametry i listeners / Section 7: FAN/ONS + listeners
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 7 / SECTION 7: FAN/ONS parametry
PROMPT --------------------------------------------------------------------------------

COLUMN param_name  FORMAT A30 HEADING "Parameter"
COLUMN param_value FORMAT A90 HEADING "Value"

SELECT name AS param_name, value AS param_value
FROM   v$parameter
WHERE  name IN ('remote_listener',
                'local_listener',
                'db_unique_name',
                'service_names',
                'log_archive_config',
                'dg_broker_start')
ORDER  BY name;

-- ============================================================================
-- SEKCJA 8: Non-replayable operations detection / Section 8: Non-replayable ops
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 8 / SECTION 8: Operacje potencjalnie nie-replayowalne
PROMPT             (heurystyka - przegladaj SQL_TEXT z V$SQL)
PROMPT --------------------------------------------------------------------------------

COLUMN sql_id       FORMAT A15 HEADING "SQL_ID"
COLUMN sql_tekst    FORMAT A80 HEADING "SQL_TEXT (trimmed)"
COLUMN ryzyko       FORMAT A30 HEADING "Ryzyko / Risk"

SELECT sql_id,
       SUBSTR(sql_text, 1, 80)                                    AS sql_tekst,
       CASE
         -- NON_REPLAYABLE - Oracle nie moze powtorzyc operacji
         WHEN UPPER(sql_text) LIKE '%ALTER SESSION%'     THEN 'ALTER SESSION w TX'
         WHEN UPPER(sql_text) LIKE '%UTL_HTTP%'          THEN 'UTL_HTTP (external)'
         WHEN UPPER(sql_text) LIKE '%UTL_SMTP%'          THEN 'UTL_SMTP (external)'
         WHEN UPPER(sql_text) LIKE '%UTL_FILE%'          THEN 'UTL_FILE (external I/O)'
         WHEN UPPER(sql_text) LIKE '%UTL_TCP%'           THEN 'UTL_TCP (external)'
         WHEN UPPER(sql_text) LIKE '%UTL_MAIL%'          THEN 'UTL_MAIL (external)'
         WHEN UPPER(sql_text) LIKE '%DBMS_PIPE%'         THEN 'DBMS_PIPE (messaging)'
         WHEN UPPER(sql_text) LIKE '%DBMS_ALERT%'        THEN 'DBMS_ALERT (messaging)'
         WHEN UPPER(sql_text) LIKE '%DBMS_AQ.%'          THEN 'DBMS_AQ (advanced queuing)'
         WHEN UPPER(sql_text) LIKE '%DBMS_LOCK%'         THEN 'DBMS_LOCK (user locks)'
         WHEN UPPER(sql_text) LIKE '%DBMS_RANDOM%'       THEN 'DBMS_RANDOM (non-deterministic)'
         WHEN UPPER(sql_text) LIKE '%DBMS_OBFUSCATION%'  THEN 'DBMS_OBFUSCATION (non-deterministic)'
         WHEN UPPER(sql_text) LIKE 'CREATE %'            THEN 'DDL (auto-commit)'
         WHEN UPPER(sql_text) LIKE 'DROP %'              THEN 'DDL (auto-commit)'
         WHEN UPPER(sql_text) LIKE 'TRUNCATE %'          THEN 'DDL (auto-commit)'
         WHEN UPPER(sql_text) LIKE 'GRANT %'             THEN 'DDL (auto-commit)'
         WHEN UPPER(sql_text) LIKE 'REVOKE %'            THEN 'DDL (auto-commit)'
         -- REQUIRES_KEEP_GRANT - Oracle moze replayowac TYLKO jesli app user ma KEEP privilege
         WHEN UPPER(sql_text) LIKE '%SYSDATE%'
           OR UPPER(sql_text) LIKE '%SYSTIMESTAMP%'
           OR UPPER(sql_text) LIKE '%CURRENT_TIMESTAMP%'
           OR UPPER(sql_text) LIKE '%CURRENT_DATE%'      THEN 'Requires GRANT KEEP DATE TIME'
         WHEN UPPER(sql_text) LIKE '%SYS_GUID%'          THEN 'Requires GRANT KEEP SYSGUID'
         WHEN UPPER(sql_text) LIKE '%.NEXTVAL%'
           OR UPPER(sql_text) LIKE '%.CURRVAL%'          THEN 'Check sequence CACHE/ORDER + KEEP'
         ELSE 'OK'
       END                                                       AS ryzyko
FROM   v$sql
WHERE  executions > 10
  AND  last_active_time > SYSDATE - 7
  AND  parsing_schema_name NOT IN ('SYS','SYSTEM','DBSNMP','APPQOSSYS','GSMADMIN_INTERNAL','XDB','MDSYS')
  AND (UPPER(sql_text) LIKE '%ALTER SESSION%'
       OR UPPER(sql_text) LIKE '%UTL_HTTP%'
       OR UPPER(sql_text) LIKE '%UTL_SMTP%'
       OR UPPER(sql_text) LIKE '%UTL_FILE%'
       OR UPPER(sql_text) LIKE '%UTL_TCP%'
       OR UPPER(sql_text) LIKE '%UTL_MAIL%'
       OR UPPER(sql_text) LIKE '%DBMS_PIPE%'
       OR UPPER(sql_text) LIKE '%DBMS_ALERT%'
       OR UPPER(sql_text) LIKE '%DBMS_AQ.%'
       OR UPPER(sql_text) LIKE '%DBMS_LOCK%'
       OR UPPER(sql_text) LIKE '%DBMS_RANDOM%'
       OR UPPER(sql_text) LIKE '%DBMS_OBFUSCATION%'
       OR UPPER(sql_text) LIKE '%SYSDATE%'
       OR UPPER(sql_text) LIKE '%SYSTIMESTAMP%'
       OR UPPER(sql_text) LIKE '%CURRENT_TIMESTAMP%'
       OR UPPER(sql_text) LIKE '%CURRENT_DATE%'
       OR UPPER(sql_text) LIKE '%SYS_GUID%'
       OR UPPER(sql_text) LIKE '%.NEXTVAL%'
       OR UPPER(sql_text) LIKE '%.CURRVAL%'
       OR UPPER(sql_text) LIKE 'CREATE %'
       OR UPPER(sql_text) LIKE 'DROP %'
       OR UPPER(sql_text) LIKE 'TRUNCATE %'
       OR UPPER(sql_text) LIKE 'GRANT %'
       OR UPPER(sql_text) LIKE 'REVOKE %')
FETCH FIRST 50 ROWS ONLY;

PROMPT
PROMPT (Jesli 0 rows = dobrze; inaczej przegladaj kod aplikacji / If 0 rows = good; otherwise review application code)

-- --------------------------------------------------------------------
-- Sekcja 8.1: KEEP grants dla user aplikacyjnych
-- Section 8.1: KEEP grants for application users
-- Bez GRANT KEEP {DATE TIME|SYSGUID|ANY SEQUENCE} mutable functions
-- NIE zwroca oryginalnej wartosci przy replay - pierwszy replay zwroci
-- inny SYSDATE/SYS_GUID niz oryginal => application-visible divergence.
-- --------------------------------------------------------------------

COLUMN grantee    FORMAT A25 HEADING "App user"
COLUMN privilege  FORMAT A25 HEADING "KEEP privilege"
COLUMN status     FORMAT A10 HEADING "Status"

SELECT grantee,
       privilege,
       'PRESENT' AS status
FROM   dba_sys_privs
WHERE  privilege IN ('KEEP DATE TIME','KEEP SYSGUID','KEEP ANY SEQUENCE')
  AND  grantee NOT IN ('SYS','SYSTEM','DBA')
ORDER  BY grantee, privilege;

PROMPT
PROMPT (Dla KAZDEGO app usera oczekiwane 3 wiersze / For EACH app user expected 3 rows: KEEP DATE TIME, KEEP SYSGUID, KEEP ANY SEQUENCE
PROMPT  Jesli brakuje - DBMS_APP_CONT_ADMIN nie zachowa mutable values podczas replay / If missing - DBMS_APP_CONT_ADMIN will not preserve mutable values during replay)

-- --------------------------------------------------------------------
-- Sekcja 8.2: Sekwencje z NOCACHE lub ORDER - zle dla TAC+RAC
-- Section 8.2: Sequences with NOCACHE/ORDER - bad for TAC+RAC
-- Male CACHE (<20) powoduje hot block na SEQ$; ORDER wymusza global lock
-- --------------------------------------------------------------------

COLUMN sequence_owner FORMAT A20 HEADING "Owner"
COLUMN sequence_name  FORMAT A30 HEADING "Sequence"
COLUMN cache_size     FORMAT 9999999 HEADING "Cache"
COLUMN order_flag     FORMAT A5 HEADING "Order"
COLUMN cycle_flag     FORMAT A5 HEADING "Cycle"

SELECT sequence_owner,
       sequence_name,
       cache_size,
       order_flag,
       cycle_flag
FROM   dba_sequences
WHERE  sequence_owner NOT IN ('SYS','SYSTEM','MDSYS','XDB','APEX_030200',
                              'CTXSYS','WMSYS','ORDSYS','APPQOSSYS',
                              'DBSNMP','GSMADMIN_INTERNAL','AUDSYS','OJVMSYS')
  AND  (cache_size < 20 OR order_flag = 'Y')
ORDER  BY sequence_owner, sequence_name;

PROMPT
PROMPT (0 wierszy = dobrze. Inaczej / 0 rows = good. Otherwise: ALTER SEQUENCE ... CACHE 1000 NOORDER
PROMPT  oraz rozwazyc GRANT KEEP ANY SEQUENCE dla replay / and consider GRANT KEEP ANY SEQUENCE for replay)

-- ============================================================================
-- SEKCJA 9: SRL (wymagany dla real-time apply + TAC) / Section 9: SRL
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 9 / SECTION 9: Standby Redo Logs (SRL)
PROMPT --------------------------------------------------------------------------------

COLUMN thread#  FORMAT 999 HEADING "Watek"
COLUMN grupy    FORMAT 999 HEADING "Grupy"
COLUMN rozmiar_mb FORMAT 99999 HEADING "Avg MB"

SELECT thread#,
       COUNT(*)                        AS grupy,
       ROUND(AVG(bytes/1024/1024), 0)  AS rozmiar_mb
FROM   v$standby_log
GROUP  BY thread#
ORDER  BY thread#;

-- ============================================================================
-- SEKCJA 10: Weryfikacja wersji klientow (przez V$SESSION_CONNECT_INFO)
-- Section 10: Client version check
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 10 / SECTION 10: Wersje klientow (JDBC/OCI)
PROMPT --------------------------------------------------------------------------------

COLUMN client_version  FORMAT A20 HEADING "Client version"
COLUMN client_driver   FORMAT A25 HEADING "Client driver"
COLUMN client_charset  FORMAT A15 HEADING "Charset"
COLUMN liczba_sesji    FORMAT 99999 HEADING "Sesje"

SELECT client_version,
       client_driver,
       client_charset,
       COUNT(*)  AS liczba_sesji
FROM   gv$session_connect_info
WHERE  client_version IS NOT NULL
GROUP  BY client_version, client_driver, client_charset
ORDER  BY COUNT(*) DESC
FETCH  FIRST 20 ROWS ONLY;

PROMPT
PROMPT (Oczekiwane / Expected: client_version >= 23.0 dla TAC; ojdbc11.jar 23ai+)

-- ============================================================================
-- SEKCJA 11: Replay statistics (jesli byly uzywane) — 26ai variant
-- Section 11: Replay statistics (if used) — 26ai variant
-- ============================================================================
-- W 26ai GV$REPLAY_STAT_SUMMARY zostal usuniety. Zastapiony per-context views:
--   GV$REPLAY_CONTEXT, GV$REPLAY_CONTEXT_LOB, GV$REPLAY_CONTEXT_SEQUENCE,
--   GV$REPLAY_CONTEXT_SYSDATE, GV$REPLAY_CONTEXT_SYSGUID, GV$REPLAY_CONTEXT_SYSTIMESTAMP
-- Tutaj agregujemy per-instance po SUM(*_VALUES_CAPTURED/REPLAYED) z GV$REPLAY_CONTEXT.
-- Status logic:
--   IDLE = no replay contexts (fresh service, no traffic)
--   PASS = wszystkie *_REPLAYED >= *_CAPTURED (success rate 100% per category)
--   WARN = jakas kategoria ma *_REPLAYED < *_CAPTURED (partial replay)
--   CRIT = nie wystepuje na poziomie context-level (failed replays maja inny mechanism w 26ai)

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 11 / SECTION 11: Replay statistics (GV$REPLAY_CONTEXT — 26ai variant)
PROMPT --------------------------------------------------------------------------------

COLUMN inst_id              FORMAT 999      HEADING "Inst"
COLUMN active_contexts      FORMAT 99999    HEADING "Ctx"
COLUMN seq_capt             FORMAT 99999999 HEADING "Seq capt"
COLUMN seq_repl             FORMAT 99999999 HEADING "Seq repl"
COLUMN sd_capt              FORMAT 99999999 HEADING "SysDate capt"
COLUMN sd_repl              FORMAT 99999999 HEADING "SysDate repl"
COLUMN sg_capt              FORMAT 99999999 HEADING "SysGUID capt"
COLUMN sg_repl              FORMAT 99999999 HEADING "SysGUID repl"
COLUMN lobs_capt            FORMAT 99999999 HEADING "LOBs capt"
COLUMN lobs_repl            FORMAT 99999999 HEADING "LOBs repl"
COLUMN ocena_tac            FORMAT A6       HEADING "Ocena"

WITH agg AS (
    SELECT inst_id,
           COUNT(*)                            AS active_contexts,
           NVL(SUM(sequence_values_captured),0)     AS seq_capt,
           NVL(SUM(sequence_values_replayed),0)     AS seq_repl,
           NVL(SUM(sysdate_values_captured),0)      AS sd_capt,
           NVL(SUM(sysdate_values_replayed),0)      AS sd_repl,
           NVL(SUM(sysguid_values_captured),0)      AS sg_capt,
           NVL(SUM(sysguid_values_replayed),0)      AS sg_repl,
           NVL(SUM(lobs_captured),0)                AS lobs_capt,
           NVL(SUM(lobs_replayed),0)                AS lobs_repl
    FROM   gv$replay_context
    GROUP  BY inst_id
)
SELECT inst_id,
       active_contexts,
       seq_capt, seq_repl,
       sd_capt,  sd_repl,
       sg_capt,  sg_repl,
       lobs_capt, lobs_repl,
       CASE
         WHEN seq_capt + sd_capt + sg_capt + lobs_capt = 0 THEN 'IDLE'
         WHEN seq_repl >= seq_capt
          AND sd_repl  >= sd_capt
          AND sg_repl  >= sg_capt
          AND lobs_repl >= lobs_capt                       THEN 'PASS'
         ELSE 'WARN'
       END                                                 AS ocena_tac
FROM   agg
ORDER  BY inst_id;

PROMPT
PROMPT (Jesli 0 wierszy = brak aktywnych replay contexts. Idealne dla swiezo / If 0 rows = no active replay contexts. Ideal for freshly
PROMPT  utworzonego service - po failoverach/replayach beda widoczne wpisy. / created service - entries will appear after failovers/replays.)
PROMPT
PROMPT Pelne zliczenie failed replays w 26ai - przez alert log / Full count of failed replays in 26ai - via alert log:
PROMPT   SELECT * FROM gv\$diag_alert_ext
PROMPT    WHERE message_text LIKE '%REPLAY%FAIL%' OR message_text LIKE '%LTXID%'
PROMPT    AND originating_timestamp > SYSDATE - 1;

-- ============================================================================
-- SEKCJA 12: Podsumowanie / Section 12: Summary
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  SEKCJA 12 / SECTION 12: Podsumowanie / Summary
PROMPT --------------------------------------------------------------------------------

WITH summary_checks AS (
    SELECT
      -- ver check
      CASE WHEN (SELECT banner_full FROM v$version WHERE banner_full LIKE '%Database%')
                LIKE '%23.%' OR
                (SELECT banner_full FROM v$version WHERE banner_full LIKE '%Database%')
                LIKE '%26.%'
           THEN 1 ELSE 0 END AS c_ver,
      -- EE
      CASE WHEN EXISTS (SELECT 1 FROM v$version WHERE banner LIKE '%Enterprise%')
           THEN 1 ELSE 0 END AS c_ee,
      -- Force logging
      CASE WHEN (SELECT force_logging FROM v$database) = 'YES' THEN 1 ELSE 0 END AS c_fl,
      -- Archivelog
      CASE WHEN (SELECT log_mode FROM v$database) = 'ARCHIVELOG' THEN 1 ELSE 0 END AS c_arc,
      -- Flashback
      CASE WHEN (SELECT flashback_on FROM v$database) = 'YES' THEN 1 ELSE 0 END AS c_fb,
      -- DBMS_APP_CONT valid
      CASE WHEN EXISTS (SELECT 1 FROM dba_objects
                        WHERE object_name='DBMS_APP_CONT'
                          AND object_type='PACKAGE'
                          AND status='VALID')
           THEN 1 ELSE 0 END AS c_tg,
      -- SRL present
      CASE WHEN (SELECT COUNT(*) FROM v$standby_log) > 0 THEN 1 ELSE 0 END AS c_srl,
      -- Any TAC service
      CASE WHEN EXISTS (SELECT 1 FROM dba_services WHERE failover_type='TRANSACTION')
           THEN 1 ELSE 0 END AS c_tac
    FROM dual
)
SELECT
    'TAC Full Readiness — podsumowanie / summary' AS sprawdzenie,
    TO_CHAR(c_ver + c_ee + c_fl + c_arc + c_fb + c_tg + c_srl + c_tac) || ' / 8' AS wartosc,
    '8 / 8'                                      AS oczekiwane,
    CASE WHEN c_ver + c_ee + c_fl + c_arc + c_fb + c_tg + c_srl + c_tac = 8 THEN 'PASS'
         WHEN c_ver + c_ee + c_fl + c_arc + c_fb + c_tg + c_srl + c_tac >= 6 THEN 'WARN'
         ELSE 'FAIL' END                         AS status
FROM summary_checks;

PROMPT
PROMPT ================================================================================
PROMPT  TAC Full Readiness check zakonczony. / TAC Full Readiness check complete.
PROMPT  Wszystkie PASS -> srodowisko gotowe do wdrozenia TAC. / All PASS -> environment ready for TAC deployment.
PROMPT  WARN -> dziala, ale zalecana poprawa przed produkcja. / WARN -> working, but improvement recommended before production.
PROMPT  FAIL -> blokuje wdrozenie, musi byc naprawione. / FAIL -> blocks deployment, must be fixed.
PROMPT ================================================================================
