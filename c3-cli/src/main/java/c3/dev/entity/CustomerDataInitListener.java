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
public class CustomerDataInitListener {
    @Inject
    @PersistenceUnit("ay")
    EntityManager em;

    @Inject
    @ConfigProperty(name = "quarkus.profile", defaultValue = "prod")
    String profile;

    @Inject
    AyConfig config;


    @Transactional
    public void onStart(@Observes StartupEvent ev) {
        if (!"dev".equals(profile)) return;
        Long count = em.createQuery("SELECT COUNT(c) FROM Customer c", Long.class).getSingleResult();
        if (count > 0) return;
        Faker faker = new Faker();
        long testDataVolume = config.testDataVolume();
        for (int i = 0; i < testDataVolume; i++) {
            Customer c = new Customer();
            c.setName(faker.name().fullName());
            c.setPhone(faker.phoneNumber().phoneNumber());
            c.setAddress(faker.address().streetAddress());
            c.setMotherName(faker.name().firstName());
            c.setFatherName(faker.name().firstName());
            c.setPreferedName(faker.name().firstName());
            c.setPreferedColor(faker.color().name());
            c.setPreferedInstrument(faker.music().instrument());
            // System.out.println(c);
            em.persist(c);
        }
    }
}
