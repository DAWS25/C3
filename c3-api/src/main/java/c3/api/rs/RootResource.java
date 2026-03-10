package c3.api.rs;

import org.jboss.resteasy.reactive.NoCache;
import org.eclipse.microprofile.config.inject.ConfigProperty;

import io.quarkus.logging.Log;
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@Path("")
public class RootResource {
    @Inject
    C3Config config;

    @ConfigProperty(name = "quarkus.http.root-path", defaultValue = "/")
    String httpPath;
    @ConfigProperty(name = "quarkus.rest.path", defaultValue = "/")
    String restPath;

    public void init(@Observes StartupEvent ev) {
        Log.infof("C3 API version[%s] initialized. message[%s]", config.version(), config.indexMessage());
        Log.infof("HTTP paths root[%s] rest[%s]", httpPath, restPath);
    }

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    @NoCache
    public String get() {
        var message = "C3 API v[" + config.version() + "] \n" + config.indexMessage();
        return message;
    }
}
