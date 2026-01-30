
package ay;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.*;
import java.util.concurrent.Callable;

import ay.model.Table;
import jakarta.enterprise.context.Dependent;
import jakarta.inject.Inject;

@Dependent
public class DisplayTask implements Callable<Void> {
    @Inject
    Execution execution;

    private int intervalSeconds = 5;

    @Override
    public Void call() {
        while (true) {
            clearScreen();
            printHeader();
            printTableAndColumnRankings();
            try {
                Thread.sleep(intervalSeconds * 1000L);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                break;
            }
        }
        return null;
    }

    private void clearScreen() {
        System.out.print("\033[H\033[2J");
        System.out.flush();
    }

    private void printHeader() {
        LocalDateTime start = execution.getStartTime();
        Duration elapsed = Duration.between(start, LocalDateTime.now());
        long seconds = elapsed.getSeconds();
        String elapsedStr = String.format("%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60);
        System.out.println("anymaise | elapsed: " + elapsedStr);
        System.out.println();
    }

    private void printTableAndColumnRankings() {
        var tableMap = execution.getTableRankings();
        if (tableMap.isEmpty()) {
            System.out.println("No tables processed yet.");
            return;
        }
        List<Table> tables = new ArrayList<>();
        for (var entry : tableMap.values()) {
            if (!Table.isIgnored(entry.ranking())) {
                tables.add(entry);
            }
        }
        // Sort tables by ranking desc
        tables.sort((a, b) -> Float.compare(b.ranking(), a.ranking()));

        // Calculate dynamic widths
        // Find the widest label among all table and column names
        int maxColNameWidth = tables.stream()
            .flatMap(t -> t.columnRecords() != null ? t.columnRecords().keySet().stream() : java.util.stream.Stream.empty())
            .mapToInt(String::length)
            .max().orElse(12);
        int maxTableNameWidth = tables.stream().mapToInt(t -> t.table().length()).max().orElse(16);
        // Add extra padding to avoid overflow
        int labelWidth = Math.max(28, Math.max(maxColNameWidth, maxTableNameWidth) + 6);
        int ratingWidth = 8;

        for (Table table : tables) {
            // Table name and rating
            System.out.printf("%-" + labelWidth + "s %" + ratingWidth + ".2f\n", table.table(), table.ranking());
            // Columns, sorted by ranking desc, printed under the table
            var columns = table.columnRecords();
            if (columns != null && !columns.isEmpty()) {
                var colList = new ArrayList<>(columns.entrySet());
                colList.removeIf(e -> Table.isIgnored(e.getValue()));
                colList.sort((a, b) -> Float.compare(b.getValue(), a.getValue()));
                for (var colEntry : colList) {
                    // Compensate label indentation so that ranks align
                    String paddedLabel = String.format("%-" + labelWidth + "s", "  " + colEntry.getKey());
                    System.out.printf("%s %" + ratingWidth + ".2f\n", paddedLabel, colEntry.getValue());
                }
            }
            System.out.println(); // Newline between tables
        }
    }


}
