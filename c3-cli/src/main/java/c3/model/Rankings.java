package ay.model;

public enum Rankings {
    HIGHEST(0.999_999F),
    HIGH(0.999F),
    LOW(0.005F),
    LOWEST(0.000_001F),
    IGNORED(-1F);

    private final float value;

    Rankings(float value) {
        this.value = value;
    }
    public float getValue() {
        return value;
    }
}