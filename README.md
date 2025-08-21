# RMA – Single Image + Postgres + pgAdmin

This setup builds **one Docker image** that runs all Spring Boot services and the RMA React UI behind Nginx, with Postgres and pgAdmin managed by Docker Compose.

## Files
- Dockerfile — multi-stage build (JARs + React) → single runtime image
- entrypoint.sh — starts Nginx and all services via Supervisor
- nginx.conf — serves `/` and proxies `/api/*` to the gateway
- docker-compose.yml — runs Postgres + db-init + app + pgAdmin

## 1) Put source zips next to the Dockerfile
- `rma_java_microservices.zip`
- `api-gateway-main.zip`
- `rma_react_frontend-main.zip`

## 2) Build the single image
```bash
docker build -t rma-one:v1 .
docker compose up -d
docker compose ps
docker compose logs -f app

remove 
docker rm -f rma-postgres


