
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

import java.time.LocalDate;
import net.datafaker.Faker;

@ApplicationScoped
public class PatientDataInitListener {
    @Inject
    @PersistenceUnit("ay")
    EntityManager em;

    @Inject
    AyConfig config;

    @Inject
    @ConfigProperty(name = "quarkus.profile")
    String profile;


    @Transactional
    public void onStart(@Observes StartupEvent ev) {
        if (!"dev".equals(profile)) return;
        Long count = em.createQuery("SELECT COUNT(p) FROM Patient p", Long.class).getSingleResult();
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
            Patient p = new Patient();
            p.setName(faker.name().fullName());
            p.setBirthDate(LocalDate.now().minusYears(20 + faker.random().nextInt(40)).minusDays(faker.random().nextInt(365)));
            p.setGender(faker.options().option("F", "M"));
            p.setAddress(faker.address().streetAddress());
            p.setEmail(faker.internet().emailAddress());
            p.setInsuranceNumber("INS" + faker.number().numberBetween(1000, 9999));
            p.setMotherName(faker.name().firstName());
            p.setFatherName(faker.name().firstName());
            p.setIcd10Code(ICD10Code.values()[faker.random().nextInt(ICD10Code.values().length)]);
            p.setNotes(faker.medical().diseaseName());
            em.persist(p);
        }
    }
}
