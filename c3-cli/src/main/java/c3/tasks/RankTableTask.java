
package ay.tasks;

import java.sql.Connection;
import java.sql.ResultSetMetaData;
import java.util.HashMap;
import java.util.Map;

import ay.Execution;
import ay.model.Cell;
import ay.model.Rankings;
import ay.model.Table;

public class RankTableTask implements Runnable {
    Execution execution;
    Connection getConnection;
    String catalog;
    String schema;
    String table;
    String type;

    public RankTableTask(Execution execution, Connection conn, String catalog, String schema, String table, String type) {
        this.execution = execution;
        this.getConnection = conn;
        this.catalog = catalog;
        this.schema = schema;
        this.table = table;
        this.type = type;
    }

    @Override
    public void run() {
        // return immediately if schema is not included
        if (!execution.isSchemaIncluded(schema)) {
            System.out.println("Skipping table in schema: " + schema);
            return;
        }
        System.out.println("Processing table: " + table);
        long rowCount = countRows();
        float samplePercentage = 0.1f;
        try {
            samplePercentage = execution.getConfig().samplePercentage();
        } catch (Exception e) {
            samplePercentage = 0;
        }
        int sampleSize = (int) Math.ceil(rowCount * samplePercentage);
        var stepSize = execution.getConfig().stepSize();
        float alpha = Rankings.HIGHEST.getValue() * stepSize / sampleSize;
        String fqtn = (catalog != null && !catalog.isEmpty()) ? String.format("%s.%s.%s", catalog, schema, table) : String.format("%s.%s", schema, table);
        String sql = "SELECT * FROM " + fqtn + " LIMIT " + sampleSize;
        Map<String, Float> columnRecords = new HashMap<>();
        try (var stmt = getConnection.createStatement(); var rs = stmt.executeQuery(sql)) {
            ResultSetMetaData meta = rs.getMetaData();
            int colCount = meta.getColumnCount();
            for (int i = 1; i <= colCount; i++) {
                columnRecords.put(meta.getColumnName(i), Rankings.HIGHEST.getValue());
            }
            while (rs.next()) {
                for (int i = 1; i <= colCount; i++) {
                    String col = meta.getColumnName(i);
                    var value = rs.getObject(i);
                    float current = columnRecords.getOrDefault(col, Rankings.HIGHEST.getValue());
                    Table tableRecord = new Table(
                        catalog,
                        schema,
                        table,
                        type,
                        rowCount,
                        null, // ranking not known yet
                        columnRecords
                    );
                    Cell cell = new Cell(
                        tableRecord,
                        col,
                        meta.getColumnTypeName(i),
                        value
                    );
                    float rank = execution.rank(cell).value();
                    float adjust = (1 - rank) * alpha;
                    float newValue = current - adjust;
                    float minValue = Rankings.LOWEST.getValue();
                    if (newValue < minValue) newValue = minValue;
                    columnRecords.put(col, newValue);
                }
            }
        } catch (Exception e) {
            System.err.println("Failed to sample rows for table " + fqtn + ": " + e.getMessage());
        }
        float ranking = columnRecords.values().stream().max(Float::compare).orElse(Rankings.IGNORED.getValue());
        this.execution.putTableRank(
            new Table(catalog, schema, table, type, rowCount, ranking, columnRecords)
        );
    }

    private long countRows() {
        long rowCount = 0L;
        String fqtn = (catalog != null && !catalog.isEmpty()) ? String.format("%s.%s.%s", catalog, schema, table) : String.format("%s.%s", schema, table);
        String sql = "SELECT COUNT(*) FROM " + fqtn;
        try (var stmt = getConnection.createStatement(); var rs = stmt.executeQuery(sql)) {
            if (rs.next()) {
                rowCount = rs.getLong(1);
            }
        } catch (Exception e) {
            System.err.println("Failed to count rows for table " + fqtn + ": " + e.getMessage());
        }
        return rowCount;
    }
}
