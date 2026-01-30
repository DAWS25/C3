package ay.dev.entity;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import jakarta.transaction.Transactional;
import jakarta.persistence.EntityManager;
import io.quarkus.hibernate.orm.PersistenceUnit;
import io.quarkus.runtime.StartupEvent;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import ay.config.AyConfig;
import net.datafaker.Faker;

@ApplicationScoped
public class ProductDataInitListener {
    @Inject
    @PersistenceUnit("ay")
    EntityManager em;

    @Inject
    AyConfig config;

    @Inject
    @ConfigProperty(name = "quarkus.profile", defaultValue = "prod")
    String profile;


    @Transactional
    public void onStart(@Observes StartupEvent ev) {
        if (!"dev".equals(profile)) return;
        Long count = em.createQuery("SELECT COUNT(p) FROM Product p", Long.class).getSingleResult();
        if (count > 0) return;
        Faker faker = new Faker();
        long testDataVolume = 100;
        try {
            testDataVolume = config.testDataVolume();
            if (testDataVolume <= 0) testDataVolume = 100;
        } catch (Exception e) {
            // fallback to default 100
        }
        for (int i = 0; i < testDataVolume; i++) {
            Product p = new Product();
            p.setName(faker.commerce().productName());
            p.setDescription(faker.commerce().material());
            p.setPrice(Double.parseDouble(faker.commerce().price()));
            em.persist(p);
        }
    }
}
