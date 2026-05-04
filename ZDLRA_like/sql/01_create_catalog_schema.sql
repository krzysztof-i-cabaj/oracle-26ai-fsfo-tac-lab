-- ==============================================================================
-- Tytul:        01_create_catalog_schema.sql
-- Opis:         Tworzy schemat wlasciciela katalogu RMAN (rman_cat) w PDB RCATPDB.
--               Nadaje role RECOVERY_CATALOG_OWNER + odpowiednie quota.
-- Description [EN]: Creates RMAN catalog owner schema (rman_cat) in RCATPDB.
--
-- Autor:        KCB Kris
-- Data:         2026-05-04 (v1.1: dodano GRANT EXECUTE ON DBMS_LOCK, lesson iter.12)
-- Wersja:       1.1
-- <repo>:       ZDLRA_like
-- Konwencje:    ZDLRA_like/SETTINGS.md
--
-- Wymagania [PL]:    - DB RCAT (CDB) + PDB RCATPDB OPEN
--                    - Tablespace USERS (default) lub dedykowany RCAT_DATA
--                    - Skrypt wymaga 1 argumentu: haslo dla rman_cat (z $LAB_PASS)
-- Requirements [EN]: - CDB RCAT + PDB RCATPDB open, 1 arg: rman_cat password ($LAB_PASS)
--
-- Uzycie [PL]:  sqlplus sys/${LAB_PASS}@rcat01:1521/RCATPDB AS SYSDBA \
--                    @01_create_catalog_schema.sql ${LAB_PASS}
-- Usage [EN]:   Same. Pass password as positional arg.
-- ==============================================================================

WHENEVER SQLERROR EXIT FAILURE
SET ECHO ON
SET FEEDBACK ON
SET VERIFY OFF

-- Pozycyjny parametr 1 = haslo dla rman_cat (z $LAB_PASS w /root/.lab_secrets)
DEFINE rman_pass = "&1"

-- Switch do PDB jesli polaczenie do CDB$ROOT
ALTER SESSION SET CONTAINER = RCATPDB;

-- Ustaw db_create_file_dest w PDB zeby OMF dzialal.
-- DBCA dla 23ai/26ai NIE ustawia tego automatycznie w PDB (lesson 2026-05-03 iter.8).
-- Path '/u02/oradata' jest zgodny z DBCA -datafileDestination z dbca_create_rcat.sh.
-- Oracle automatycznie umiesci pliki PDB w '/u02/oradata/RCAT/<PDB_GUID>/' (zgodnie z konwencja).
-- DBCA in 23ai/26ai does NOT auto-set db_create_file_dest in PDB. Set it explicitly so OMF works.
ALTER SYSTEM SET db_create_file_dest = '/u02/oradata' SCOPE=BOTH;

-- Tablespace dedykowany dla katalogu (lepsza separacja niz USERS).
-- Uzywamy Oracle Managed Files (OMF): bez DATAFILE clause - Oracle umieszcza plik
-- w db_create_file_dest (ustawione powyzej) z auto-generated nazwa zawierajaca GUID PDB.
-- Powod (lesson learned 2026-05-03 iter.8): hardcoded sciezka '/u02/oradata/RCAT/rcatpdb/rcat_data01.dbf'
-- zwracala ORA-01119 bo DBCA tworzyla PDB jako 'RCATPDB' (uppercase) lub z GUID, nie 'rcatpdb'.
-- OMF to robi bezpiecznie: Oracle wie gdzie sa pliki PDB (kazda PDB ma swoj subdir z GUID).
-- Use Oracle Managed Files (OMF): no DATAFILE clause - Oracle places it in db_create_file_dest
-- with auto-generated name including PDB GUID. Hardcoded path failed ORA-01119 because DBCA
-- creates PDB dir with GUID/uppercase, not lowercase 'rcatpdb'.
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM dba_tablespaces WHERE tablespace_name = 'RCAT_DATA';
    IF v_count = 0 THEN
        EXECUTE IMMEDIATE q'[
            CREATE TABLESPACE rcat_data
            DATAFILE SIZE 500M AUTOEXTEND ON NEXT 100M MAXSIZE 10G
            EXTENT MANAGEMENT LOCAL AUTOALLOCATE
            SEGMENT SPACE MANAGEMENT AUTO
        ]';
        DBMS_OUTPUT.PUT_LINE('Created tablespace RCAT_DATA (OMF in db_create_file_dest)');
    ELSE
        DBMS_OUTPUT.PUT_LINE('Tablespace RCAT_DATA already exists, skipping');
    END IF;
END;
/

-- User rman_cat
DECLARE
    v_count NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_count FROM dba_users WHERE username = 'RMAN_CAT';
    IF v_count = 0 THEN
        EXECUTE IMMEDIATE 'CREATE USER rman_cat IDENTIFIED BY "&rman_pass" ' ||
            'DEFAULT TABLESPACE rcat_data ' ||
            'TEMPORARY TABLESPACE temp ' ||
            'QUOTA UNLIMITED ON rcat_data';
        DBMS_OUTPUT.PUT_LINE('Created user RMAN_CAT');
    ELSE
        DBMS_OUTPUT.PUT_LINE('User RMAN_CAT already exists, skipping CREATE');
    END IF;
END;
/

-- Grants
GRANT CONNECT, RESOURCE TO rman_cat;
GRANT RECOVERY_CATALOG_OWNER TO rman_cat;
GRANT CREATE SESSION TO rman_cat;
GRANT CREATE TABLE TO rman_cat;
GRANT CREATE VIEW TO rman_cat;
GRANT CREATE PROCEDURE TO rman_cat;

-- Lesson learned 2026-05-04 iter.12: w 26ai role RECOVERY_CATALOG_OWNER NIE daje
-- automatycznie EXECUTE na DBMS_LOCK. Bez tego grantu kazdy `rman target / catalog ...`
-- failuje z PLS-00201 'identifier DBMS_LOCK must be declared' przy proibe upgrade lock-u
-- katalogu (RMAN sprawdza wersje schematu przy connect i probuje wziac DBMS_LOCK).
-- Konsekwencja: BACKUP DATABASE PLUS ARCHIVELOG przerwany po fazie ARCHIVELOG, samo
-- DATABASE niezbackupowane. Empirycznie potwierdzone, naprawione GRANT-em ponizej.
-- Lesson 2026-05-04 iter.12: in 26ai RECOVERY_CATALOG_OWNER role does NOT auto-grant
-- EXECUTE on DBMS_LOCK. Without it `rman target / catalog ...` fails with PLS-00201
-- when RMAN tries to acquire upgrade lock on connect.
GRANT EXECUTE ON SYS.DBMS_LOCK TO rman_cat;

-- Walidacja
SELECT username, default_tablespace, account_status FROM dba_users WHERE username = 'RMAN_CAT';
SELECT granted_role FROM dba_role_privs WHERE grantee = 'RMAN_CAT' ORDER BY 1;

-- Walidacja DBMS_LOCK grant (lesson iter.12) - musi pokazac 1 wiersz EXECUTE
SELECT grantee, table_name, privilege FROM dba_tab_privs
 WHERE grantee = 'RMAN_CAT' AND table_name = 'DBMS_LOCK';

PROMPT ============================================================
PROMPT [OK] Schemat rman_cat utworzony w PDB RCATPDB
PROMPT [OK] rman_cat schema created in PDB RCATPDB
PROMPT
PROMPT Nastepny krok / Next step:
PROMPT   rman catalog rman_cat/${LAB_PASS}@rcat01:1521/RCATPDB @02_create_catalog.sql
PROMPT ============================================================

EXIT
