package c3.api.rs;

import io.quarkus.runtime.annotations.StaticInitSafe;
import io.smallrye.config.ConfigMapping;
import io.smallrye.config.WithDefault;
import io.smallrye.config.WithName;
import io.quarkus.logging.Log;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Optional;

@ConfigMapping(prefix = "c3")
@StaticInitSafe
public interface C3Config {
    @WithDefault("Welcome to C3 API")
    String indexMessage();

    @WithName("version")
    Optional<String> configuredVersion();

    default String version(){
        return configuredVersion()
            .filter(v -> !v.isBlank())
            .or(C3Config::getVersionFromFiles)
            .orElse("0.0.0");
    }

    private static Optional<String> getVersionFromFiles() {
        Path[] roots = new Path[] {
            Path.of("."),
            Path.of(".."),
            Path.of("../..")
        };

        for (Path root : roots) {
            Path xPath = root.resolve("version.x.txt");
            Path yPath = root.resolve("version.y.txt");
            Path zPath = root.resolve("version.z.txt");

            if (!Files.isRegularFile(xPath) || !Files.isRegularFile(yPath) || !Files.isRegularFile(zPath)) {
                continue;
            }

            try {
                String x = Files.readString(xPath).trim();
                String y = Files.readString(yPath).trim();
                String z = Files.readString(zPath).trim();

                if (!x.isBlank() && !y.isBlank() && !z.isBlank()) {
                    return Optional.of(x + "." + y + "." + z);
                }
            } catch (IOException ignored) {
                Log.debugf( "Failed to read version files in [%s]: %s", root, ignored.getMessage());
            }
        }

        return Optional.empty();
    }
}
