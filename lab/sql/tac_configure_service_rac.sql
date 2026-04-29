-- ==============================================================================
-- Tytul:        tac_configure_service_rac.sql
-- Opis:         Konfiguracja TAC service (srvctl + DBMS_SERVICE).
--               Generator komend srvctl oraz skrypt SQL dla DBMS_SERVICE.MODIFY_SERVICE.
--               Stosuje wzorzec dry-run: KROK 1 (podglad) -> KROK 2 (zmiana) -> KROK 3 (weryfikacja).
-- Description [EN]: TAC service configuration (srvctl + DBMS_SERVICE).
--                   Generates srvctl commands + SQL for DBMS_SERVICE.MODIFY_SERVICE.
--                   Uses dry-run pattern: STEP 1 (preview) -> STEP 2 (change) -> STEP 3 (verify).
--
-- Autor:        KCB Kris
-- Data:         2026-04-23
-- Wersja:       1.0
--
-- Wymagania [PL]:    - Oracle 23ai/26ai EE, RAC, CDB+PDB (skrypt jest CDB-aware)
--                    - Uprawnienia DBA (lub EXECUTE na DBMS_SERVICE)
-- Requirements [EN]: - Oracle 23ai/26ai EE, RAC, CDB+PDB (script is CDB-aware)
--                    - DBA privs (or EXECUTE on DBMS_SERVICE)
--
-- Uzycie [PL]:       sqlconn.sh -s PRIM -i -f sql/tac_configure_service_rac.sql
-- Usage [EN]:        sqlconn.sh -s PRIM -i -f sql/tac_configure_service_rac.sql
-- ==============================================================================

SET PAGESIZE 200
SET LINESIZE 220
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING ON
SET SERVEROUTPUT ON SIZE UNLIMITED

-- Parametry (override przez DEFINE przed uruchomieniem)
DEFINE db_name       = 'PRIM'
DEFINE pdb_name      = 'APPPDB'
DEFINE service_rw    = 'MYAPP_TAC'
DEFINE service_ro    = 'MYAPP_RO'
DEFINE preferred_inst1 = 'PRIM1'
DEFINE preferred_inst2 = 'PRIM2'

PROMPT ================================================================================
PROMPT    TAC Service Configuration for &db_name
PROMPT ================================================================================
PROMPT

-- ============================================================================
-- KROK 1 / STEP 1: Podglad aktualnego stanu / Preview current state
-- ============================================================================

PROMPT --------------------------------------------------------------------------------
PROMPT  KROK 1 / STEP 1: Aktualna konfiguracja services / Current services config
PROMPT --------------------------------------------------------------------------------

COLUMN name                    FORMAT A25 HEADING "Service"
COLUMN con_id                  FORMAT 999 HEADING "Con"
COLUMN failover_type           FORMAT A15 HEADING "Failover type"
COLUMN failover_restore        FORMAT A8  HEADING "Restore"
COLUMN failover_retries        FORMAT 99999 HEADING "Retries"
COLUMN commit_outcome          FORMAT A6  HEADING "Commit"
COLUMN retention_timeout       FORMAT 999999 HEADING "Retention"
COLUMN session_state_consistency FORMAT A10 HEADING "Session"
COLUMN clb_goal                FORMAT A10 HEADING "CLB"
COLUMN aq_ha_notifications     FORMAT A4 HEADING "FAN"

-- F-06: cdb_services + filtr con_id > 1 = serwisy aplikacyjne w PDB.
-- F-15: usunieto failover_method (TAF artefakt - dla TAC ignorowany).
-- F-02: dodano failover_restore (LEVEL1 wymagany dla TAC w 26ai).
-- F-06/15/02: cdb_services for PDB-scoped services; failover_method removed; failover_restore added.
SELECT
    name,
    con_id,
    failover_type,
    failover_restore,
    failover_retries,
    commit_outcome,
    retention_timeout,
    session_state_consistency,
    clb_goal,
    aq_ha_notifications
FROM   cdb_services
WHERE  con_id > 1
  AND  (name IN ('&service_rw', '&service_ro') OR name NOT LIKE 'SYS%');

PROMPT
PROMPT Aktualnie zdefiniowane service'y (cdb_services - PDB-scoped, con_id > 1):
SELECT name, con_id
FROM   cdb_services
WHERE  con_id > 1
  AND  name NOT LIKE 'SYS%'
  AND  name NOT LIKE '%XDB%'
  AND  name NOT LIKE '%CDB%'
ORDER  BY con_id, name;

-- ============================================================================
-- KROK 2 / STEP 2: Generator komend srvctl / srvctl commands generator
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  KROK 2 / STEP 2: srvctl commands do wykonania / srvctl commands to execute
PROMPT --------------------------------------------------------------------------------

BEGIN
    DBMS_OUTPUT.PUT_LINE('-- ============================================================');
    DBMS_OUTPUT.PUT_LINE('-- TAC SERVICE SETUP — &db_name');
    DBMS_OUTPUT.PUT_LINE('-- Wykonaj z OS (jako oracle user) / Execute from OS');
    DBMS_OUTPUT.PUT_LINE('-- ============================================================');
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE('-- Sprawdz czy service juz istnieje / Check if exists');
    DBMS_OUTPUT.PUT_LINE('srvctl config service -d &db_name -s &service_rw 2>/dev/null || echo "Service nie istnieje"');
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE('-- === 1. TAC service (RW, role PRIMARY, PDB &pdb_name) ===');
    -- F-06: -pdb <PDB_NAME> dla CDB-aware service registration.
    -- F-02: -failover_restore LEVEL1 jest WYMAGANY dla TAC replay w 26ai.
    DBMS_OUTPUT.PUT_LINE('srvctl add service -d &db_name -s &service_rw \');
    DBMS_OUTPUT.PUT_LINE('  -pdb &pdb_name \');
    DBMS_OUTPUT.PUT_LINE('  -preferred &preferred_inst1,&preferred_inst2 \');
    DBMS_OUTPUT.PUT_LINE('  -failovertype TRANSACTION \');
    DBMS_OUTPUT.PUT_LINE('  -failover_restore LEVEL1 \');
    DBMS_OUTPUT.PUT_LINE('  -failoverretry 30 \');
    DBMS_OUTPUT.PUT_LINE('  -failoverdelay 10 \');
    DBMS_OUTPUT.PUT_LINE('  -replay_init_time 900 \');
    DBMS_OUTPUT.PUT_LINE('  -commit_outcome TRUE \');
    DBMS_OUTPUT.PUT_LINE('  -retention 86400 \');
    DBMS_OUTPUT.PUT_LINE('  -session_state DYNAMIC \');
    DBMS_OUTPUT.PUT_LINE('  -drain_timeout 300 \');
    DBMS_OUTPUT.PUT_LINE('  -stopoption IMMEDIATE \');
    DBMS_OUTPUT.PUT_LINE('  -role PRIMARY \');
    DBMS_OUTPUT.PUT_LINE('  -notification TRUE \');
    DBMS_OUTPUT.PUT_LINE('  -clbgoal SHORT');
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE('-- === 2. Read-only service (role PHYSICAL_STANDBY, dla ADG) ===');
    DBMS_OUTPUT.PUT_LINE('-- Uzywane tylko gdy posiadasz opcje Active Data Guard');
    DBMS_OUTPUT.PUT_LINE('srvctl add service -d &db_name -s &service_ro \');
    DBMS_OUTPUT.PUT_LINE('  -pdb &pdb_name \');
    DBMS_OUTPUT.PUT_LINE('  -preferred &preferred_inst1 \');
    DBMS_OUTPUT.PUT_LINE('  -role PHYSICAL_STANDBY \');
    DBMS_OUTPUT.PUT_LINE('  -failovertype SELECT \');
    DBMS_OUTPUT.PUT_LINE('  -notification TRUE \');
    DBMS_OUTPUT.PUT_LINE('  -clbgoal LONG');
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE('-- === 3. Start services ===');
    DBMS_OUTPUT.PUT_LINE('srvctl start service -d &db_name -s &service_rw');
    DBMS_OUTPUT.PUT_LINE('# &service_ro uruchomi sie automatycznie na bazie z rola PHYSICAL_STANDBY');
    DBMS_OUTPUT.PUT_LINE('');

    DBMS_OUTPUT.PUT_LINE('-- === 4. Verify ===');
    DBMS_OUTPUT.PUT_LINE('srvctl config service -d &db_name -s &service_rw');
    DBMS_OUTPUT.PUT_LINE('srvctl status service -d &db_name -s &service_rw');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- Expected output fragmenty (srvctl config service):');
    DBMS_OUTPUT.PUT_LINE('--   Service role:                PRIMARY');
    DBMS_OUTPUT.PUT_LINE('--   Pluggable database name:     &pdb_name');
    DBMS_OUTPUT.PUT_LINE('--   Failover type:               TRANSACTION');
    DBMS_OUTPUT.PUT_LINE('--   Failover restore:            LEVEL1   <-- F-02');
    DBMS_OUTPUT.PUT_LINE('--   Commit Outcome:              true     (slownik cdb_services.commit_outcome zwraca YES)');
    DBMS_OUTPUT.PUT_LINE('--   Retention:                   86400 seconds');
    DBMS_OUTPUT.PUT_LINE('--   Replay Initiation Time:      900 seconds');
    DBMS_OUTPUT.PUT_LINE('--   Drain timeout:               300 seconds');
    DBMS_OUTPUT.PUT_LINE('--   Session State Consistency:   DYNAMIC');
    DBMS_OUTPUT.PUT_LINE('--   Notification:                TRUE (FAN)');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- ============================================================');

END;
/

-- ============================================================================
-- Alternatywa: DBMS_SERVICE.MODIFY_SERVICE (dla Single Instance lub istniejacych services)
-- Alternative: DBMS_SERVICE.MODIFY_SERVICE (for Single Instance or existing services)
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  ALTERNATYWA: DBMS_SERVICE (jesli service juz istnieje)
PROMPT  ALTERNATIVE: DBMS_SERVICE (if service already exists)
PROMPT --------------------------------------------------------------------------------

PROMPT
PROMPT Aby wykonac: zdejmij komentarz z bloku PL/SQL ponizej i uruchom ponownie
PROMPT To execute: uncomment the PL/SQL block below and re-run

/*
BEGIN
    DBMS_SERVICE.MODIFY_SERVICE(
        service_name              => '&service_rw',
        failover_method           => DBMS_SERVICE.FAILOVER_METHOD_NONE,
        failover_type             => DBMS_SERVICE.FAILOVER_TYPE_TRANSACTION,
        failover_retries          => 30,
        failover_delay            => 10,
        clb_goal                  => DBMS_SERVICE.CLB_GOAL_SHORT,
        aq_ha_notifications       => TRUE,
        commit_outcome            => TRUE,
        retention_timeout         => 86400,
        replay_initiation_timeout => 900,
        session_state_consistency => 'DYNAMIC',
        drain_timeout             => 300
    );
    DBMS_OUTPUT.PUT_LINE('Service &service_rw zmodyfikowany pomyslnie.');
END;
/
*/

-- ============================================================================
-- KROK 3 / STEP 3: Weryfikacja (uruchom po wykonaniu srvctl) / Verification
-- ============================================================================

PROMPT
PROMPT --------------------------------------------------------------------------------
PROMPT  KROK 3 / STEP 3: Weryfikacja (po wykonaniu komend srvctl)
PROMPT                     Verification (after executing srvctl commands)
PROMPT --------------------------------------------------------------------------------

PROMPT
PROMPT Uruchom ponownie ten skrypt lub wykonaj:
PROMPT   SELECT name, con_id, failover_type, failover_restore, commit_outcome,
PROMPT          retention_timeout, session_state_consistency, drain_timeout,
PROMPT          aq_ha_notifications
PROMPT   FROM   cdb_services
PROMPT   WHERE  name = '&service_rw' AND con_id > 1;
PROMPT
PROMPT Oczekiwane wartosci / Expected values (slownik cdb_services):
PROMPT   failover_type              = TRANSACTION
PROMPT   failover_restore           = LEVEL1   (F-02 - obowiazkowe dla TAC w 26ai)
PROMPT   commit_outcome             = YES      (F-25 - slownik 26ai zwraca YES, nie TRUE)
PROMPT   retention_timeout          = 86400
PROMPT   session_state_consistency  = DYNAMIC
PROMPT   drain_timeout              = 300
PROMPT   aq_ha_notifications        = YES

-- Wykonanie weryfikacji jesli service istnieje
SELECT
    name               AS nazwa_serwisu,
    con_id             AS con_id,
    failover_type      AS typ_failover,
    failover_restore   AS restore_mode,
    commit_outcome     AS commit_outcome,
    retention_timeout  AS retencja_sek,
    session_state_consistency AS consistency_sesji,
    drain_timeout      AS drain_sek,
    aq_ha_notifications AS fan
FROM   cdb_services
WHERE  name = '&service_rw'
  AND  con_id > 1;

PROMPT
PROMPT ================================================================================
PROMPT  Zapamietaj: powtorz ten skrypt dla STBY (role PRIMARY na STBY = po switchoverze)
PROMPT  Remember: repeat this script for STBY (role PRIMARY on STBY = post-switchover)
PROMPT ================================================================================
