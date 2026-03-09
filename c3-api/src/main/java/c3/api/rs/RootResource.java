package c3.api.rs;

import org.jboss.resteasy.reactive.NoCache;

import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("")
public class RootResource {
    @Inject
    C3Config config;

    @ConfigProperty(name = "quarkus.http.root-path") 
    String httpPath;
    @ConfigProperty(name = "quarkus.rest.path") 
    String restPath;

    public void init(@Observes StartupEvent ev) {
        Log.info("C3 API version[%s] initialized. message[%s]", config.version(), config.indexMessage());
        Log.info("HTTP paths root[%s] rest[%s]", httpPath, restPath);
    }

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    @NoCache
    public String get() {
        return config.indexMessage();
    }
}
