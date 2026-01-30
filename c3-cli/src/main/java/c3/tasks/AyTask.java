package ay.tasks;

import java.time.Duration;
import java.util.concurrent.Callable;

import javax.sql.DataSource;

import ay.Execution;
import jakarta.enterprise.context.Dependent;
import jakarta.inject.Inject;

import java.sql.Connection;
import java.sql.SQLException;
import java.sql.ResultSet;
import java.sql.DatabaseMetaData;

@Dependent
public class AyTask implements Callable<Void> {
    @Inject
    Execution execution;

    @Inject
    @io.quarkus.agroal.DataSource("ay")
    DataSource ds;

    

    @Override
    public Void call() throws Exception {
        try (Connection conn = ds.getConnection()) {
            pingDatabase(conn);
            iterateTables(conn);
            Thread.sleep(5 * 60 * 1000); // Sleep for 5 minutes
        } catch (SQLException e) {
            throw new RuntimeException("Failed to validate database connection or iterate tables", e);
        }
        return null;

    }

    private void pingDatabase(Connection conn) throws SQLException {
        if (!conn.isValid(2)) { // 2 seconds timeout
            throw new SQLException("Database connection is not valid");
        }
    }

    private void iterateTables(Connection conn) throws SQLException {
        DatabaseMetaData meta = conn.getMetaData();
        //TODO: add getTables() params according to configuration
        String catalog = null;
        String schema = null;
        try (ResultSet rs = meta.getTables(catalog, schema, "%", new String[] {"TABLE"})) {
            while (rs.next()) {
                String tableName = rs.getString("TABLE_NAME");
                String tableCatalog = rs.getString("TABLE_CAT");
                String tableSchema = rs.getString("TABLE_SCHEM");
                String tableType = rs.getString("TABLE_TYPE");
                Runnable tableTask = new RankTableTask(execution, conn, tableCatalog, tableSchema, tableName, tableType);
                Thread.startVirtualThread(tableTask);
            }
        }
    }
}
