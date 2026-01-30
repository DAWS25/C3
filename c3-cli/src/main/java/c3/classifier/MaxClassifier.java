
package ay.classifier;

import ay.model.*;
import io.quarkus.logging.Log;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import jakarta.enterprise.inject.Instance;

@ApplicationScoped
@Composite
public class MaxClassifier implements Classifier {
    @Inject
    @Single
    Instance<Classifier> singleClassifiers;

    public void init(@Observes StartupEvent ev) {
        var count = singleClassifiers.stream().count();
        Log.infof("Initialized %s classifiers.",count);
    }

    @Override
    public Ranking rank(Cell cell) {
        return singleClassifiers.stream()
            .map(c -> c.rank(cell))
            .max((a, b) -> Float.compare(a.value(), b.value()))
            .get();
    }
}
