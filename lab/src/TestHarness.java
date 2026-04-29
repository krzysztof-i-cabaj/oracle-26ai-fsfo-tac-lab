// ==============================================================================
// Tytul:        TestHarness.java
// Opis:         UCP + TAC test client. Petla INSERT/COMMIT do app_user.test_log
//               przez service MYAPP_TAC. Po failover klient kontynuuje przez
//               TAC replay (failover_restore=LEVEL1) bez interwencji.
// Description [EN]: UCP + TAC test client. Loop INSERT/COMMIT through MYAPP_TAC.
//                   Survives failover via TAC replay (failover_restore=LEVEL1).
//
// Autor:        KCB Kris
// Data:         2026-04-27
// Wersja:       3.0 (VMs2-install) - F-09: env password + SQLRecoverableException + zalecane Maven build
//
// Wymagania [PL]:    - JDK 17+ z opensami modulow (--add-opens) wymaganymi przez UCP 23.x.
//                    - ojdbc11 23.5+ i ucp11 23.5+ na classpath (zob. src/pom.xml).
//                    - Zmienna srodowiskowa APP_PASSWORD (haslo aplikacyjne dla app_user).
// Requirements [EN]: - JDK 17+ with --add-opens for UCP 23.x; ojdbc11 23.5+ + ucp11 23.5+;
//                      env var APP_PASSWORD set.
//
// Uzycie [PL]:
//   APP_PASSWORD='Oracle26ai_LAB!' \
//     java --add-opens=java.base/java.lang=ALL-UNNAMED \
//          --add-opens=java.base/java.util=ALL-UNNAMED \
//          --add-opens=java.base/jdk.internal.misc=ALL-UNNAMED \
//          --add-opens=java.base/sun.nio.ch=ALL-UNNAMED \
//          -cp '/opt/lab/jars/*:.' TestHarness
// ==============================================================================

import oracle.ucp.jdbc.PoolDataSource;
import oracle.ucp.jdbc.PoolDataSourceFactory;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.SQLRecoverableException;
import java.time.Instant;

public class TestHarness {

    // Konwencja laboratorium: pojedyncze haslo dla wszystkich kont (root/oracle/grid/SYS/SYSTEM/
    // PDB Admin/ASM/wallet/app_user) - 'Oracle26ai_LAB!'. W produkcji ustaw APP_PASSWORD env var
    // i nie polegaj na fallbacku.
    // Lab convention: all accounts share one password. In production set APP_PASSWORD env, do not
    // rely on the fallback below.
    private static final String LAB_DEFAULT_PASSWORD = "Oracle26ai_LAB!";

    public static void main(String[] args) throws Exception {
        // F-09: priorytet env (APP_PASSWORD lub LAB_PASS) > fallback do labowego defaultu.
        // F-09: env precedence (APP_PASSWORD or LAB_PASS) > lab default fallback.
        String appPassword = System.getenv("APP_PASSWORD");
        if (appPassword == null || appPassword.isEmpty()) {
            appPassword = System.getenv("LAB_PASS");
        }
        if (appPassword == null || appPassword.isEmpty()) {
            appPassword = LAB_DEFAULT_PASSWORD;
            System.out.println("[INFO] APP_PASSWORD/LAB_PASS env nieustawione - uzywam labowego defaultu.");
        }

        PoolDataSource pds = PoolDataSourceFactory.getPoolDataSource();

        // Krytyczne dla TAC: uzycie klasy Replay (OracleDataSourceImpl) a nie standardowej.
        pds.setConnectionFactoryClassName("oracle.jdbc.replay.OracleDataSourceImpl");
        pds.setURL("jdbc:oracle:thin:@MYAPP_TAC");
        pds.setUser("app_user");
        pds.setPassword(appPassword);

        // Parametry puli.
        pds.setInitialPoolSize(5);
        pds.setMinPoolSize(5);
        pds.setMaxPoolSize(20);
        pds.setConnectionWaitTimeout(10);
        pds.setInactiveConnectionTimeout(300);
        pds.setValidateConnectionOnBorrow(true);

        // ONS i FAN events do obslugi przelaczen miedzy wezlami
        // (nodes spoiwo prim01/prim02 RAC + stby01 SI Restart - F-13 ons.config).
        pds.setFastConnectionFailoverEnabled(true);
        pds.setONSConfiguration("nodes=prim01.lab.local:6200,prim02.lab.local:6200,stby01.lab.local:6200");

        System.out.println("UCP skonfigurowane pomyslnie.");
        System.out.println("  Sterownik: " + pds.getConnectionFactoryClassName());
        System.out.println("  URL:       " + pds.getURL());
        System.out.println("Start petli transakcyjnej (Ctrl+C przerywa)...");
        System.out.println();

        long loop = 0;
        long replayCount = 0;
        long fatalCount = 0;
        while (true) {
            loop++;
            try (Connection conn = pds.getConnection()) {
                // Explicit transaction control - wymagane przez TAC Replay (FIX-088).
                conn.setAutoCommit(false);

                String instance = "unknown";
                int sid = 0;

                try (PreparedStatement ps0 = conn.prepareStatement(
                        "SELECT sys_context('USERENV','INSTANCE_NAME'), sys_context('USERENV','SID') FROM dual");
                     ResultSet rs = ps0.executeQuery()) {
                    if (rs.next()) {
                        instance = rs.getString(1);
                        sid = rs.getInt(2);
                    }
                }

                try (PreparedStatement ps = conn.prepareStatement(
                        "INSERT INTO app_user.test_log (instance, session_id, message) VALUES (?, ?, ?)")) {
                    ps.setString(1, instance);
                    ps.setInt(2, sid);
                    ps.setString(3, "loop=" + loop + " ts=" + Instant.now());
                    int rows = ps.executeUpdate();
                    conn.commit();
                    System.out.println("[" + loop + "] SUKCES: " + instance
                        + "  SID=" + sid + "  rows=" + rows);
                }
            } catch (SQLRecoverableException e) {
                // F-09: rozroznij recoverable (failover, drain, replay-pending) od fatal.
                // F-09: Distinguish recoverable (failover/drain/replay-pending) from fatal.
                replayCount++;
                System.out.println("[" + loop + "] RECOVERABLE (TAC replay/failover): "
                    + e.getErrorCode() + " - " + e.getMessage());
            } catch (SQLException e) {
                // Bledy logiczne (constraint violation, ORA-00942 itp.) NIE sa kandydatami na replay.
                fatalCount++;
                System.out.println("[" + loop + "] FATAL SQL: " + e.getErrorCode()
                    + " - " + e.getMessage());
            } catch (Exception e) {
                fatalCount++;
                System.out.println("[" + loop + "] FATAL: " + e.getClass().getSimpleName()
                    + " - " + e.getMessage());
            }
            if (loop % 60 == 0) {
                System.out.printf("== status: loop=%d  replay=%d  fatal=%d ==%n",
                    loop, replayCount, fatalCount);
            }
            Thread.sleep(1000);
        }
    }
}
