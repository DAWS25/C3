package ay;

import java.time.LocalDateTime;
import java.util.concurrent.atomic.AtomicInteger;

import ay.config.AyConfig;
import ay.model.Cell;
import ay.model.Ranking;
import ay.model.Table;
import ay.classifier.*;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.Map;

import io.quarkus.logging.Log;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;


@ApplicationScoped
public class Execution {
    @Inject
    AyConfig config;

    private final LocalDateTime startTime;
    // Map of table name to TableRecord, preserves insertion order
    private final Map<String, Table> tableRankings = Collections.synchronizedMap(new LinkedHashMap<>());
    
    public Execution() {
        this.startTime = LocalDateTime.now();
    }

    public AyConfig getConfig() {
        return config;
    }
    
    
    public LocalDateTime getStartTime() {
        return startTime;
    }


    public void putTableRank(Table record) {
        Log.infof("Ranking table %s with ranking %s, rows %d", record.table(), record.ranking(), record.rowCount());
        tableRankings.put(record.table(), record);
    }

    public Table getTableRecord(String tableName){
        return tableRankings.get(tableName);
    }
    
    @Override
    public String toString() {
        return "Execution{" +
                "startTime=" + startTime +
                '}';
    }

     public Map<String, Table> getTableRankings() {
         return tableRankings;
     }

    public boolean isSchemaIncluded(String schema) {
        return getConfig().includeSchemas().contains(schema.toUpperCase());
    }

    @Inject
    @Composite
    Classifier classifier;
    public Ranking rank(Cell cell) {
        return classifier.rank(cell);
    }
}
