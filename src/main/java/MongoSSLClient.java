

import com.mongodb.MongoClientSettings;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import com.mongodb.client.MongoDatabase;
import org.bson.Document;

import javax.net.ssl.SSLContext;
import java.io.FileInputStream;
import java.security.KeyStore;
import javax.net.ssl.TrustManagerFactory;

public class MongoSSLClient {
    public static void main(String[] args) throws Exception {
        String trustStorePath = "./truststore/mongo-truststore.jks";
        char[] trustStorePassword = "changeit".toCharArray();

        KeyStore trustStore = KeyStore.getInstance(KeyStore.getDefaultType());
        trustStore.load(new FileInputStream(trustStorePath), trustStorePassword);

        TrustManagerFactory tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        tmf.init(trustStore);

        SSLContext sslContext = SSLContext.getInstance("TLS");
        sslContext.init(null, tmf.getTrustManagers(), null);

        MongoClientSettings settings = MongoClientSettings.builder()
                .applyToSslSettings(builder -> builder.enabled(true).context(sslContext))
                .applyConnectionString(new com.mongodb.ConnectionString(
                        "mongodb://root:rootpass@localhost:27017/?authSource=admin&ssl=true"))
                .build();

        try (MongoClient mongoClient = MongoClients.create(settings)) {
            MongoDatabase db = mongoClient.getDatabase("testdb");
            db.getCollection("test").insertOne(new Document("msg", "Hello TLS!"));
            System.out.println("[INFO] Inserted document via SSL/TLS");
        }
    }
}
