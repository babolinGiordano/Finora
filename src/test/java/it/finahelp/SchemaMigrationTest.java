package it.finahelp;

import io.quarkus.test.junit.QuarkusTest;
import jakarta.inject.Inject;
import org.junit.jupiter.api.Test;

import javax.sql.DataSource;
import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Smoke test dello step 0: verifica che Dev Services alzi Postgres e che Flyway
 * applichi V1. Se questo test passa, l'infrastruttura di base funziona.
 */
@QuarkusTest
class SchemaMigrationTest {

    @Inject
    DataSource dataSource;

    @Test
    void flywayHasAppliedInitialMigration() throws Exception {
        try (Connection c = dataSource.getConnection();
             Statement s = c.createStatement();
             ResultSet rs = s.executeQuery(
                     "select version, success from flyway_schema_history order by installed_rank")) {
            assertTrue(rs.next(), "nessuna migrazione applicata");
            assertEquals("1", rs.getString("version"));
            assertTrue(rs.getBoolean("success"));
            assertFalse(rs.next(), "attesa una sola migrazione");
        }
    }

    @Test
    void allTablesOfTheSchemaExist() throws Exception {
        List<String> tables = new ArrayList<>();
        try (Connection c = dataSource.getConnection();
             Statement s = c.createStatement();
             ResultSet rs = s.executeQuery(
                     "select table_name from information_schema.tables where table_schema = 'public'")) {
            while (rs.next()) {
                tables.add(rs.getString(1));
            }
        }
        assertTrue(tables.containsAll(List.of(
                        "account", "category", "import_batch", "transaction", "categorization_rule",
                        "instrument", "trade", "instrument_price", "allocation_target", "proposal")),
                "tabelle trovate: " + tables);
    }
}
