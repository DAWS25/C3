package c3.api.rs;

import io.smallrye.config.ConfigMapping;
import io.smallrye.config.WithDefault;

@ConfigMapping(prefix = "c3")
public interface C3Config {
    @WithDefault("Welcome to C3 API")
    String indexMessage();
}
