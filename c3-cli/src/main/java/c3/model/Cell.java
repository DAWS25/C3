package ay.model;

public record Cell(
    Table tableRecord,
    String columnName,
    String columnType,
    Object value
) {}
