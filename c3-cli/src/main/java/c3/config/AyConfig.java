package ay.config;

import java.util.List;

import io.smallrye.config.ConfigMapping;
import io.smallrye.config.WithDefault;

@ConfigMapping(prefix = "ay")
public interface AyConfig {
    @WithDefault("PUBLIC")
    List<String> includeSchemas();

    @WithDefault("0.2")
    float samplePercentage();

    @WithDefault("0.90")
    float stepSize();

    @WithDefault("0.80")
    float rankingThreshold();

    @WithDefault("0.80")
    float confidenceThreshold();

    @WithDefault("100")
    Long testDataVolume();

}
