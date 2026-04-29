-- ==============================================================================
-- Tytul:        fsfo_configure_broker.sql
-- Opis:         Generator komend dgmgrl do konfiguracji brokera + FSFO.
--               Zapisuje plik .dgmgrl do review przez DBA przed wykonaniem.
-- Description [EN]: dgmgrl command generator for broker + FSFO configuration.
--                   Writes .dgmgrl script for DBA review before execution.
--
-- Autor:        KCB Kris
-- Data:         2026-04-23
-- Wersja:       1.0
--
-- Wymagania [PL]:    - Oracle 19c+ EE z wlaczonym DG Broker (dg_broker_start=TRUE)
--                    - Static listener skonfigurowane (PRIM_DGMGRL, STBY_DGMGRL)
--                    - Broker musi byc pusty (przed CREATE CONFIGURATION)
-- Requirements [EN]: - Oracle 19c+ EE with DG Broker enabled
--                    - Static listeners configured (PRIM_DGMGRL, STBY_DGMGRL)
--                    - Broker must be empty (before CREATE CONFIGURATION)
--
-- Uzycie [PL]:       sqlconn.sh -s PRIM -i -f sql/fsfo_configure_broker.sql -o broker_setup.dgmgrl
--                    Potem: review broker_setup.dgmgrl, a nastepnie:
--                    dgmgrl sys/@PRIM_ADMIN @broker_setup.dgmgrl
-- Usage [EN]:        sqlconn.sh -s PRIM -i -f sql/fsfo_configure_broker.sql -o broker_setup.dgmgrl
--                    Then: review broker_setup.dgmgrl and run:
--                    dgmgrl sys/@PRIM_ADMIN @broker_setup.dgmgrl
-- ==============================================================================

SET PAGESIZE 0
SET LINESIZE 300
SET TRIMSPOOL ON
SET FEEDBACK OFF
SET VERIFY OFF
SET HEADING OFF
SET TERMOUT OFF
SET SERVEROUTPUT ON SIZE UNLIMITED

-- Domyslne wartosci (mozna nadpisac interaktywnie jesli TERMOUT=ON)
DEFINE config_name      = 'DG_CONFIG_PRIM_STBY'
DEFINE primary_db       = 'PRIM'
DEFINE primary_scan     = 'scan-dc.corp.local'
DEFINE standby_db       = 'STBY'
DEFINE standby_scan     = 'scan-dr.corp.local'
DEFINE protection_mode  = 'MAXAVAILABILITY'

-- FSFO parameters (z Quick Reference)
DEFINE fsfo_threshold         = 30
DEFINE fsfo_lag_limit         = 30
DEFINE fsfo_auto_reinstate    = TRUE
DEFINE observer_override      = TRUE
DEFINE observer_reconnect     = 10

-- Observer hosts
DEFINE obs_master_name   = 'obs_ext'
DEFINE obs_master_host   = 'host-ext-obs.corp.local'
DEFINE obs_backup1_name  = 'obs_dc'
DEFINE obs_backup1_host  = 'host-dc-obs.corp.local'
DEFINE obs_backup2_name  = 'obs_dr'
DEFINE obs_backup2_host  = 'host-dr-obs.corp.local'

DEFINE obs_log_dir = '/var/log/oracle/observer'

SET TERMOUT ON

BEGIN
    DBMS_OUTPUT.PUT_LINE('-- ============================================================');
    DBMS_OUTPUT.PUT_LINE('-- BROKER + FSFO setup script (auto-generated)');
    DBMS_OUTPUT.PUT_LINE('-- Generated: ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
    DBMS_OUTPUT.PUT_LINE('-- Review this script carefully before executing!');
    DBMS_OUTPUT.PUT_LINE('-- ============================================================');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- Execute via:');
    DBMS_OUTPUT.PUT_LINE('--   dgmgrl sys/@&primary_db._ADMIN @broker_setup.dgmgrl');
    DBMS_OUTPUT.PUT_LINE('-- ============================================================');
    DBMS_OUTPUT.PUT_LINE('');

    -- Pre-flight
    DBMS_OUTPUT.PUT_LINE('-- Krok 0: Sprawdzenie czy broker uruchomiony / Verify broker running');
    DBMS_OUTPUT.PUT_LINE('SHOW CONFIGURATION;');
    DBMS_OUTPUT.PUT_LINE('-- Expected: ORA-16532 (no broker configuration) jesli swiezo');
    DBMS_OUTPUT.PUT_LINE('');

    -- CREATE CONFIGURATION
    DBMS_OUTPUT.PUT_LINE('-- Krok 1: Create configuration');
    DBMS_OUTPUT.PUT_LINE('CREATE CONFIGURATION ''&config_name'' AS');
    DBMS_OUTPUT.PUT_LINE('  PRIMARY DATABASE IS ''&primary_db''');
    DBMS_OUTPUT.PUT_LINE('  CONNECT IDENTIFIER IS ''&primary_db'';');
    DBMS_OUTPUT.PUT_LINE('');

    -- ADD DATABASE
    DBMS_OUTPUT.PUT_LINE('-- Krok 2: Add standby database');
    DBMS_OUTPUT.PUT_LINE('ADD DATABASE ''&standby_db'' AS');
    DBMS_OUTPUT.PUT_LINE('  CONNECT IDENTIFIER IS ''&standby_db''');
    DBMS_OUTPUT.PUT_LINE('  MAINTAINED AS PHYSICAL;');
    DBMS_OUTPUT.PUT_LINE('');

    -- Transport properties
    DBMS_OUTPUT.PUT_LINE('-- Krok 3: Redo transport properties (SYNC + AFFIRM dla MaxAvailability)');
    DBMS_OUTPUT.PUT_LINE('EDIT DATABASE ''&primary_db'' SET PROPERTY ''LogXptMode''=''SYNC'';');
    DBMS_OUTPUT.PUT_LINE('EDIT DATABASE ''&standby_db'' SET PROPERTY ''LogXptMode''=''SYNC'';');
    DBMS_OUTPUT.PUT_LINE('EDIT DATABASE ''&primary_db'' SET PROPERTY ''LogShipping''=''ON'';');
    DBMS_OUTPUT.PUT_LINE('EDIT DATABASE ''&standby_db'' SET PROPERTY ''LogShipping''=''ON'';');
    DBMS_OUTPUT.PUT_LINE('EDIT DATABASE ''&primary_db'' SET PROPERTY ''DelayMins''=''0'';');
    DBMS_OUTPUT.PUT_LINE('EDIT DATABASE ''&standby_db'' SET PROPERTY ''DelayMins''=''0'';');
    DBMS_OUTPUT.PUT_LINE('EDIT DATABASE ''&primary_db'' SET PROPERTY ''NetTimeout''=''30'';');
    DBMS_OUTPUT.PUT_LINE('EDIT DATABASE ''&standby_db'' SET PROPERTY ''NetTimeout''=''30'';');
    DBMS_OUTPUT.PUT_LINE('');

    -- Redo apply
    DBMS_OUTPUT.PUT_LINE('-- Krok 4: Redo apply settings (real-time apply)');
    DBMS_OUTPUT.PUT_LINE('EDIT DATABASE ''&standby_db'' SET PROPERTY ''ApplyInstanceTimeout''=''0'';');
    DBMS_OUTPUT.PUT_LINE('EDIT DATABASE ''&standby_db'' SET PROPERTY ''ApplyParallel''=''AUTO'';');
    DBMS_OUTPUT.PUT_LINE('');

    -- ENABLE CONFIGURATION
    DBMS_OUTPUT.PUT_LINE('-- Krok 5: Enable configuration (activate broker)');
    DBMS_OUTPUT.PUT_LINE('ENABLE CONFIGURATION;');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- Poczekaj az STBY aktywnie apply redo / Wait for STBY to catch up');
    DBMS_OUTPUT.PUT_LINE('-- dgmgrl prompt> HOST sleep 30;');
    DBMS_OUTPUT.PUT_LINE('');

    -- Verify
    DBMS_OUTPUT.PUT_LINE('-- Krok 6: Verify configuration');
    DBMS_OUTPUT.PUT_LINE('SHOW CONFIGURATION;');
    DBMS_OUTPUT.PUT_LINE('SHOW DATABASE ''&primary_db'';');
    DBMS_OUTPUT.PUT_LINE('SHOW DATABASE ''&standby_db'';');
    DBMS_OUTPUT.PUT_LINE('-- Expected: Configuration Status: SUCCESS');
    DBMS_OUTPUT.PUT_LINE('');

    -- Protection mode
    DBMS_OUTPUT.PUT_LINE('-- Krok 7: Set protection mode');
    DBMS_OUTPUT.PUT_LINE('EDIT CONFIGURATION SET PROTECTION MODE AS &protection_mode;');
    DBMS_OUTPUT.PUT_LINE('');

    -- FSFO properties
    DBMS_OUTPUT.PUT_LINE('-- Krok 8: FSFO properties');
    DBMS_OUTPUT.PUT_LINE('EDIT CONFIGURATION SET PROPERTY FastStartFailoverThreshold=&fsfo_threshold;');
    DBMS_OUTPUT.PUT_LINE('EDIT CONFIGURATION SET PROPERTY FastStartFailoverLagLimit=&fsfo_lag_limit;');
    DBMS_OUTPUT.PUT_LINE('EDIT CONFIGURATION SET PROPERTY FastStartFailoverAutoReinstate=&fsfo_auto_reinstate;');
    DBMS_OUTPUT.PUT_LINE('EDIT CONFIGURATION SET PROPERTY ObserverOverride=&observer_override;');
    DBMS_OUTPUT.PUT_LINE('EDIT CONFIGURATION SET PROPERTY ObserverReconnect=&observer_reconnect;');
    DBMS_OUTPUT.PUT_LINE('');

    -- Observer registration
    DBMS_OUTPUT.PUT_LINE('-- Krok 9: Register observers (3 hosts DC/DR/EXT)');
    DBMS_OUTPUT.PUT_LINE('ADD OBSERVER ''&obs_master_name'' ON ''&obs_master_host''');
    DBMS_OUTPUT.PUT_LINE('  LOG FILE IS ''&obs_log_dir/&obs_master_name..log'';');
    DBMS_OUTPUT.PUT_LINE('ADD OBSERVER ''&obs_backup1_name'' ON ''&obs_backup1_host''');
    DBMS_OUTPUT.PUT_LINE('  LOG FILE IS ''&obs_log_dir/&obs_backup1_name..log'';');
    DBMS_OUTPUT.PUT_LINE('ADD OBSERVER ''&obs_backup2_name'' ON ''&obs_backup2_host''');
    DBMS_OUTPUT.PUT_LINE('  LOG FILE IS ''&obs_log_dir/&obs_backup2_name..log'';');
    DBMS_OUTPUT.PUT_LINE('');

    -- Master observer
    DBMS_OUTPUT.PUT_LINE('-- Krok 10: Designate master observer (on EXT — third site)');
    DBMS_OUTPUT.PUT_LINE('SET MASTEROBSERVER TO &obs_master_name;');
    DBMS_OUTPUT.PUT_LINE('');

    -- Enable FSFO
    DBMS_OUTPUT.PUT_LINE('-- Krok 11: Enable Fast-Start Failover');
    DBMS_OUTPUT.PUT_LINE('ENABLE FAST_START FAILOVER;');
    DBMS_OUTPUT.PUT_LINE('');

    -- Start observers (UWAGA: robione PRZEZ systemd na hostach, nie tutaj)
    DBMS_OUTPUT.PUT_LINE('-- Krok 12: Start observers (uruchom na kazdym hoscie OSOBNO przez systemd)');
    DBMS_OUTPUT.PUT_LINE('-- Na host-ext-obs:');
    DBMS_OUTPUT.PUT_LINE('--   sudo systemctl start dgmgrl-observer-ext');
    DBMS_OUTPUT.PUT_LINE('-- Na host-dc-obs:');
    DBMS_OUTPUT.PUT_LINE('--   sudo systemctl start dgmgrl-observer-dc');
    DBMS_OUTPUT.PUT_LINE('-- Na host-dr-obs:');
    DBMS_OUTPUT.PUT_LINE('--   sudo systemctl start dgmgrl-observer-dr');
    DBMS_OUTPUT.PUT_LINE('');

    -- Final verification
    DBMS_OUTPUT.PUT_LINE('-- Krok 13: Final verification');
    DBMS_OUTPUT.PUT_LINE('SHOW CONFIGURATION;');
    DBMS_OUTPUT.PUT_LINE('SHOW FAST_START FAILOVER;');
    DBMS_OUTPUT.PUT_LINE('SHOW OBSERVER;');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- Expected:');
    DBMS_OUTPUT.PUT_LINE('--   Configuration Status: SUCCESS');
    DBMS_OUTPUT.PUT_LINE('--   Fast-Start Failover: Enabled in Potential Data Loss Mode');
    DBMS_OUTPUT.PUT_LINE('--   Master Observer: &obs_master_name (connected)');
    DBMS_OUTPUT.PUT_LINE('--   Backup observers: &obs_backup1_name, &obs_backup2_name (connected)');
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('-- ============================================================');
    DBMS_OUTPUT.PUT_LINE('-- End of broker setup script');
    DBMS_OUTPUT.PUT_LINE('-- ============================================================');
END;
/
