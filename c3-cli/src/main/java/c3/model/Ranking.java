package ay.model;

public record Ranking(
    float value,
    float confidence
) {
    public static Ranking of(float value) {
        return new Ranking(value, 1.0f);
    }
}
