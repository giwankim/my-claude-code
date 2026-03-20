# Spring Initializr Dependencies

Group structure reference for organizing dependencies by category.
The live catalog is fetched at runtime via `spring init --list` for up-to-date
IDs, descriptions, and version compatibility. This file provides the grouping
that the CLI output lacks.

Use the **ID** values with the `spring init -d` flag.

## 1. Developer Tools

| ID | Name | Description |
|----|------|-------------|
| native | GraalVM Native Support | Compile Spring apps to native executables |
| dgs-codegen | GraphQL DGS Code Generation | Generate types and APIs for GraphQL |
| devtools | Spring Boot DevTools | Fast restarts, LiveReload, enhanced dev experience |
| lombok | Lombok | Annotation library to reduce boilerplate |
| configuration-processor | Spring Configuration Processor | Metadata for IDE help and code completion |
| docker-compose | Docker Compose Support | Docker compose integration for development |
| modulith | Spring Modulith | Build modular monolithic applications |

## 2. Web

| ID | Name | Description |
|----|------|-------------|
| web | Spring Web | Build web/REST apps with Spring MVC + Tomcat |
| webflux | Spring Reactive Web | Build reactive web apps with WebFlux + Netty |
| spring-restclient | HTTP Client | RestClient and RestTemplate integration |
| spring-webclient | Reactive HTTP Client | WebClient integration |
| graphql | Spring for GraphQL | Build GraphQL applications |
| data-rest | Rest Repositories | Expose Spring Data repos over REST |
| session-data-mongodb | Spring Session for MongoDB | Session management with MongoDB |
| session-data-redis | Spring Session for Redis | Session management with Redis |
| session-hazelcast | Spring Session for Hazelcast | Session management with Hazelcast |
| session-jdbc | Spring Session for JDBC | Session management with JDBC |
| data-rest-explorer | Rest Repositories HAL Explorer | Browse REST repos in browser |
| hateoas | Spring HATEOAS | HATEOAS-compliant RESTful APIs |
| web-services | Spring Web Services | Contract-first SOAP development |
| jersey | Jersey | JAX-RS RESTful Web Services |
| vaadin | Vaadin | Full-stack web platform; views in Java or React |
| netflix-dgs | Netflix DGS | GraphQL applications with Netflix DGS |
| htmx | htmx | Modern UIs with hypertext simplicity |
| springdoc-openapi | SpringDoc OpenAPI | OpenAPI/Swagger documentation |

## 3. Template Engines

| ID | Name | Description |
|----|------|-------------|
| thymeleaf | Thymeleaf | Server-side Java template engine |
| freemarker | Apache Freemarker | Text output from templates and data |
| mustache | Mustache | Logic-less templates |
| groovy-templates | Groovy Templates | Groovy templating engine |
| jte | jte | Secure, lightweight templates for Java/Kotlin |

## 4. Security

| ID | Name | Description |
|----|------|-------------|
| security | Spring Security | Authentication and access-control |
| oauth2-client | OAuth2 Client | OAuth2/OpenID Connect client |
| oauth2-authorization-server | OAuth2 Authorization Server | Spring Authorization Server |
| oauth2-resource-server | OAuth2 Resource Server | OAuth2 resource server |
| security-saml2 | SAML 2.0 | SAML 2.0 integration |
| spring-security-webauthn | WebAuthn | WebAuthn support |
| ldap | LDAP | Directory services protocol |
| data-ldap | Spring Data LDAP | Spring Data for LDAP |
| okta | Okta | Okta OAuth2 integration |

## 5. SQL

| ID | Name | Description |
|----|------|-------------|
| jdbc | JDBC API | Database connectivity |
| r2dbc | R2DBC API | Reactive database connectivity |
| data-jpa | Spring Data JPA | Persist data with JPA + Hibernate |
| data-jdbc | Spring Data JDBC | Persist data with plain JDBC |
| data-r2dbc | Spring Data R2DBC | Reactive relational data access |
| mybatis | MyBatis Framework | Custom SQL and stored procedures |
| liquibase | Liquibase Migration | Database migration and source control |
| flyway | Flyway Migration | Schema migration version control |
| jooq | JOOQ Access Layer | Type-safe SQL queries from generated code |
| db2 | IBM DB2 Driver | JDBC driver for DB2 |
| derby | Apache Derby Database | Java relational database |
| h2 | H2 Database | Fast in-memory database |
| hsql | HyperSQL Database | Lightweight Java SQL engine |
| mariadb | MariaDB Driver | JDBC/R2DBC driver |
| sqlserver | MS SQL Server Driver | JDBC/R2DBC driver for SQL Server |
| mysql | MySQL Driver | JDBC driver |
| oracle | Oracle Driver | JDBC driver |
| postgresql | PostgreSQL Driver | JDBC/R2DBC driver |

## 6. NoSQL

| ID | Name | Description |
|----|------|-------------|
| data-redis | Spring Data Redis | Synchronous/reactive Redis access |
| data-redis-reactive | Spring Data Reactive Redis | Reactive Redis access |
| mongodb | MongoDB | NoSQL document database |
| data-mongodb | Spring Data MongoDB | Spring Data for MongoDB |
| data-mongodb-reactive | Spring Data Reactive MongoDB | Reactive MongoDB access |
| elasticsearch | Elasticsearch | Distributed search and analytics |
| data-elasticsearch | Spring Data Elasticsearch | Spring Data for Elasticsearch |
| cassandra | Cassandra | Distributed database |
| data-cassandra | Spring Data for Cassandra | Spring Data for Cassandra |
| data-cassandra-reactive | Spring Data Reactive for Cassandra | Reactive Cassandra access |
| couchbase | Couchbase | Document-oriented NoSQL database |
| data-couchbase | Spring Data Couchbase | Spring Data for Couchbase |
| data-couchbase-reactive | Spring Data Reactive Couchbase | Reactive Couchbase access |
| neo4j | Neo4j | Graph database |
| data-neo4j | Spring Data Neo4j | Spring Data for Neo4j |

## 7. Messaging

| ID | Name | Description |
|----|------|-------------|
| integration | Spring Integration | Enterprise Integration Patterns |
| amqp | Spring for RabbitMQ | RabbitMQ messaging |
| amqp-streams | Spring for RabbitMQ Streams | RabbitMQ stream processing |
| kafka | Spring for Apache Kafka | Kafka pub/sub and streaming |
| kafka-streams | Spring for Apache Kafka Streams | Kafka Streams processing |
| activemq | Spring for Apache ActiveMQ 5 | ActiveMQ Classic messaging |
| artemis | Spring for Apache ActiveMQ Artemis | ActiveMQ Artemis messaging |
| pulsar | Spring for Apache Pulsar | Apache Pulsar messaging |
| pulsar-reactive | Spring for Apache Pulsar (Reactive) | Reactive Pulsar messaging |
| websocket | WebSocket | WebSocket with SockJS |
| rsocket | RSocket | RSocket networking |
| camel | Apache Camel | System integration framework |
| solace | Solace PubSub+ | Pub/sub and message replay |

## 8. I/O

| ID | Name | Description |
|----|------|-------------|
| batch | Spring Batch | Batch processing with transactions |
| batch-jdbc | Spring Batch JDBC | JDBC support for Spring Batch |
| hazelcast | Hazelcast | Distributed cache and compute |
| validation | Validation | Bean Validation with Hibernate |
| mail | Java Mail Sender | Email via JavaMailSender |
| quartz | Quartz Scheduler | Job scheduling |
| cache | Spring Cache Abstraction | Caching with pluggable providers |
| spring-shell | Spring Shell | Command line applications |
| spring-grpc-server | Spring gRPC Server | gRPC server support |
| spring-grpc-client | Spring gRPC Client | gRPC client support |

## 9. Ops

| ID | Name | Description |
|----|------|-------------|
| actuator | Spring Boot Actuator | Monitoring and management endpoints |
| sbom-cyclone-dx | CycloneDX SBOM support | Software Bill of Materials |
| codecentric-spring-boot-admin-client | Spring Boot Admin (Client) | Register with Admin Server |
| codecentric-spring-boot-admin-server | Spring Boot Admin (Server) | Admin UI for Spring Boot apps |
| sentry | Sentry | Error tracking and performance monitoring |
| cloudfoundry | Cloud Foundry | Cloud-native platform support |

## 10. Observability

| ID | Name | Description |
|----|------|-------------|
| datadog | Datadog | Metrics to Datadog |
| dynatrace | Dynatrace | Metrics to Dynatrace |
| influx | Influx | Metrics to InfluxDB |
| graphite | Graphite | Metrics to Graphite |
| new-relic | New Relic | Metrics to New Relic |
| otlp-metrics | OTLP for metrics | Metrics via OpenTelemetry Protocol |
| prometheus | Prometheus | Prometheus-format metrics |
| datasource-micrometer | Datasource Micrometer | JDBC observability |
| distributed-tracing | Distributed Tracing | Span and trace IDs in logs |
| opentelemetry | OpenTelemetry | OpenTelemetry metrics/traces |
| wavefront | Wavefront | Metrics to Tanzu Observability |
| zipkin | Zipkin | Distributed tracing with Zipkin |

## 11. Testing

| ID | Name | Description |
|----|------|-------------|
| restdocs | Spring REST Docs | Auto-generated REST documentation |
| testcontainers | Testcontainers | Docker-based test containers |
| cloud-contract-verifier | Contract Verifier | Consumer Driven Contracts |
| cloud-contract-stub-runner | Contract Stub Runner | WireMock stub runner |
| unboundid-ldap | Embedded LDAP Server | In-memory LDAP for tests |

## 12. Spring Cloud

| ID | Name | Description |
|----|------|-------------|
| cloud-starter | Cloud Bootstrap | Non-specific Spring Cloud features |
| cloud-function | Function | Serverless business logic |
| cloud-task | Task | Short-lived microservices |

## 13. Spring Cloud Config

| ID | Name | Description |
|----|------|-------------|
| cloud-config-client | Config Client | Connect to Config Server |
| cloud-config-server | Config Server | Central config via Git/SVN/Vault |
| cloud-starter-vault-config | Vault Configuration | HashiCorp Vault config |
| cloud-starter-zookeeper-config | Apache Zookeeper Configuration | Zookeeper config |
| cloud-starter-consul-config | Consul Configuration | Consul config |

## 14. Spring Cloud Discovery

| ID | Name | Description |
|----|------|-------------|
| cloud-eureka | Eureka Discovery Client | Service discovery client |
| cloud-eureka-server | Eureka Server | Service discovery server |
| cloud-starter-zookeeper-discovery | Apache Zookeeper Discovery | Zookeeper discovery |
| cloud-starter-consul-discovery | Consul Discovery | Consul discovery |

## 15. Spring Cloud Routing

| ID | Name | Description |
|----|------|-------------|
| cloud-gateway | Gateway | API routing with security |
| cloud-gateway-reactive | Reactive Gateway | Reactive API routing |
| cloud-feign | OpenFeign | Declarative REST client |
| cloud-loadbalancer | Cloud LoadBalancer | Client-side load balancing |

## 16. Spring Cloud Circuit Breaker

| ID | Name | Description |
|----|------|-------------|
| cloud-resilience4j | Resilience4J | Circuit breaker implementation |

## 17. Spring Cloud Messaging

| ID | Name | Description |
|----|------|-------------|
| cloud-bus | Cloud Bus | Lightweight message broker for state changes |
| cloud-stream | Cloud Stream | Event-driven microservices |

## 18. VMware Tanzu

### Application Service

| ID | Name | Description |
|----|------|-------------|
| scs-config-client | Config Client (TAS) | Config on VMware Tanzu |
| scs-service-registry | Service Registry (TAS) | Eureka on VMware Tanzu |

### Spring Enterprise Extensions

| ID | Name | Description |
|----|------|-------------|
| tanzu-governance-starter | Governance Starter | Cipher/TLS compliance |
| tanzu-scg-access-control | SCG Access Control | API key/JWT access control |
| tanzu-scg-custom | SCG Custom | Custom filters and predicates |
| tanzu-scg-graphql | SCG GraphQL | Restrict GraphQL operations |
| tanzu-scg-sso | SCG Single Sign On | SSO and role-based routing |
| tanzu-scg-traffic-control | SCG Traffic Control | Rate limiting and circuit breakers |
| tanzu-scg-transformation | SCG Transformation | Response transformation |

## 19. AI

### LLM Providers

| ID | Name | Description |
|----|------|-------------|
| spring-ai-anthropic | Anthropic Claude | Claude AI models |
| spring-ai-azure-openai | Azure OpenAI | Azure-hosted ChatGPT |
| spring-ai-bedrock | Amazon Bedrock | Bedrock Cohere/Titan models |
| spring-ai-bedrock-converse | Amazon Bedrock Converse | Enhanced Bedrock features |
| spring-ai-deepseek | DeepSeek | DeepSeek AI models |
| spring-ai-google-genai | Google GenAI | Gemini models |
| spring-ai-huggingface | HuggingFace | HuggingFace models |
| spring-ai-minimax | MiniMax | MiniMax AI models |
| spring-ai-mistral | Mistral AI | Mistral generative models |
| spring-ai-oci-genai | OCI GenAI | Oracle Cloud AI models |
| spring-ai-ollama | Ollama | Run LLMs locally |
| spring-ai-openai | OpenAI | ChatGPT and DALL-E |
| spring-ai-openai-sdk | OpenAI SDK | Official OpenAI SDK integration |
| spring-ai-vertexai-gemini | Vertex AI Gemini | Google Vertex Gemini |
| spring-ai-zhipuai | ZhipuAI | ZhipuAI models |

### Embeddings

| ID | Name | Description |
|----|------|-------------|
| spring-ai-google-genai-embedding | Google GenAI Embeddings | Google embedding models |
| spring-ai-vertexai-embeddings | Vertex AI Embeddings | Vertex text/multimodal embeddings |
| spring-ai-transformers | Transformers (ONNX) | Pre-trained ONNX transformer models |
| spring-ai-postgresml | PostgresML | PostgresML text embeddings |

### Vector Databases

| ID | Name | Description |
|----|------|-------------|
| spring-ai-vectordb-azure | Azure AI Search | Azure vector search |
| spring-ai-vectordb-cassandra | Cassandra Vector DB | Cassandra vector storage |
| spring-ai-vectordb-chroma | Chroma Vector DB | Embeddings with metadata |
| spring-ai-vectordb-couchbase | Couchbase Vector DB | Couchbase vector search |
| spring-ai-vectordb-elasticsearch | Elasticsearch Vector DB | Elasticsearch vectors |
| spring-ai-vectordb-gemfire | GemFire Vector DB | GemFire vector storage |
| spring-ai-vectordb-milvus | Milvus Vector DB | High-performance vector search |
| spring-ai-vectordb-mongodb-atlas | MongoDB Atlas Vector DB | MongoDB vector search |
| spring-ai-vectordb-neo4j | Neo4j Vector DB | Neo4j vector search |
| spring-ai-vectordb-opensearch | OpenSearch Vector DB | OpenSearch vectors |
| spring-ai-vectordb-aws-opensearch | AWS OpenSearch Vector DB | AWS OpenSearch vectors |
| spring-ai-vectordb-oracle | Oracle Vector DB | Oracle Database 23ai vectors |
| spring-ai-vectordb-pgvector | PGvector Vector DB | PostgreSQL vector extension |
| spring-ai-vectordb-pinecone | Pinecone Vector DB | Cloud vector search |
| spring-ai-vectordb-qdrant | Qdrant Vector DB | Open-source vector search |
| spring-ai-vectordb-redis | Redis Vector DB | Redis vector search |
| spring-ai-vectordb-s3 | S3 Vector DB | S3 vector storage |
| spring-ai-vectordb-mariadb | MariaDB Vector DB | MariaDB 11.7 vector search |
| spring-ai-vectordb-azurecosmosdb | Azure Cosmos DB Vector Store | Cosmos DB vectors |
| spring-ai-vectordb-typesense | Typesense Vector DB | Typesense vector search |
| spring-ai-vectordb-weaviate | Weaviate Vector DB | Weaviate ML embeddings |
| spring-ai-vectordb-bedrock-knowledgebase | Bedrock Knowledge Base | Managed RAG |

### Chat Memory Repositories

| ID | Name | Description |
|----|------|-------------|
| spring-ai-chat-memory-repository-in-memory | In-memory | In-memory chat storage |
| spring-ai-chat-memory-repository-jdbc | JDBC | JDBC-based chat memory |
| spring-ai-chat-memory-repository-cassandra | Cassandra | Cassandra chat memory |
| spring-ai-chat-memory-repository-mongodb | MongoDB | MongoDB chat memory |
| spring-ai-chat-memory-repository-neo4j | Neo4j | Neo4j chat memory |
| spring-ai-chat-memory-repository-cosmos-db | Azure Cosmos DB | Cosmos DB chat memory |
| spring-ai-chat-memory-repository-redis | Redis | Redis chat memory |

### Document Readers

| ID | Name | Description |
|----|------|-------------|
| spring-ai-markdown-document-reader | Markdown Reader | Convert Markdown to Documents |
| spring-ai-tika-document-reader | Tika Reader | Extract text from various formats |
| spring-ai-pdf-document-reader | PDF Reader | Extract text from PDFs |
| spring-ai-jsoup-document-reader | JSoup Reader | Parse HTML to Documents |

### Other AI

| ID | Name | Description |
|----|------|-------------|
| spring-ai-elevenlabs | ElevenLabs | Text-to-speech |
| spring-ai-mcp-server | MCP Server | Model Context Protocol server |
| spring-ai-mcp-client | MCP Client | Model Context Protocol client |
| mcp-security | MCP Security [Experimental] | Security for MCP server/client and OAuth2 Authorization Server |
| spring-ai-stabilityai | Stability AI | Text-to-image generation |
| timefold-solver | Timefold Solver | Operations and scheduling optimization |

## 20. Microsoft Azure

| ID | Name | Description |
|----|------|-------------|
| azure-support | Azure Support | Azure auto-configuration |
| azure-active-directory | Azure Active Directory | Azure AD + Spring Security |
| azure-cosmos-db | Azure Cosmos DB | NoSQL with Spring Data |
| azure-keyvault | Azure Key Vault | Secrets and certificates |
| azure-storage | Azure Storage | Blob, fileshare, and queue |

## 21. Google Cloud

| ID | Name | Description |
|----|------|-------------|
| cloud-gcp | Google Cloud Support | Google Cloud auto-configuration |
| cloud-gcp-pubsub | Google Cloud Messaging | Pub/Sub integration |
| cloud-gcp-storage | Google Cloud Storage | Storage integration |
