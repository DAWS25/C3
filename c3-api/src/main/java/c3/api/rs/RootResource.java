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

    @GET
    @Produces(MediaType.TEXT_PLAIN)
    @NoCache
    public String get() {
        return config.indexMessage();
    }
}
