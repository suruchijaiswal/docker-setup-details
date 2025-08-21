# ================================
# Stage 1: Build Spring Boot JARs
# ================================
FROM maven:3.9-eclipse-temurin-21 AS builder-java
RUN apt-get update && apt-get install -y --no-install-recommends unzip && rm -rf /var/lib/apt/lists/*
WORKDIR /src

# Put these ZIPs next to this Dockerfile before building:
# - rma_java_microservices.zip
# - api-gateway-main.zip
COPY rma_java_microservices.zip /src/
COPY api-gateway-main.zip      /src/

# Unzip and build all Maven modules (skip tests)
RUN unzip -q rma_java_microservices.zip -d rma_java_microservices && \
    unzip -q api-gateway-main.zip      -d api-gateway-main && \
    set -eux; \
    find /src -name "pom.xml" -maxdepth 4 | sort -u > /tmp/poms.txt; \
    while read -r P; do \
      echo "Building $P"; \
      mvn -B -q -DskipTests \
          -Dmaven.wagon.http.retryHandler.count=3 \
          -Dmaven.wagon.http.connectionTimeout=60000 \
          -Dmaven.wagon.http.pool=false \
          -f "$P" clean package; \
    done < /tmp/poms.txt; \
    mkdir -p /out/jars && \
    find /src -type f -path "*/target/*" -name "*.jar" -exec cp {} /out/jars/ \;

# =====================================
# Stage 2: Build the RMA React frontend
# =====================================
FROM node:20-alpine AS builder-react
RUN apk add --no-cache unzip
WORKDIR /ui

# Put this ZIP next to the Dockerfile before building:
# - rma_react_frontend-main.zip
COPY rma_react_frontend-main.zip /ui/

# Unzip and build; auto-detect common toolchains; fallback if no build script
RUN unzip -q rma_react_frontend-main.zip -d rma && \
    set -eux; \
    APPDIR="$(find /ui/rma -maxdepth 1 -mindepth 1 -type d | head -n1)"; \
    cd "$APPDIR"; \
    if [ -f yarn.lock ]; then corepack enable || true; yarn install --frozen-lockfile || yarn install; \
    else npm ci || npm install; fi; \
    if npm run -s | grep -q '^  build'; then \
      npm run build; \
    elif grep -q '"vite"' package.json; then \
      npx --yes vite build; \
    elif grep -q '"react-scripts"' package.json; then \
      npx --yes react-scripts build; \
    elif grep -q '"next"' package.json; then \
      npx --yes next build && npx --yes next export -o build; \
    else \
      echo "No standard build found; creating placeholder build/"; \
      mkdir -p build && printf '<!doctype html><meta charset=utf-8><title>RMA</title><h1>UI build not provided</h1>' > build/index.html; \
    fi; \
    mkdir -p /out/ui-root && \
    if [ -d build ]; then cp -r build /out/ui-root/; \
    elif [ -d dist ]; then cp -r dist /out/ui-root/build; \
    else cp -r . /out/ui-root/build; fi

# =================================
# Stage 3: Final runtime (single OS)
# =================================
FROM eclipse-temurin:21-jre

# Nginx + Supervisor to run multiple processes
RUN apt-get update && apt-get install -y --no-install-recommends supervisor nginx ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Folders
RUN mkdir -p /app/services /var/log/supervisor /var/www/ui

# Artifacts
COPY --from=builder-java  /out/jars          /app/services/
COPY --from=builder-react /out/ui-root/build /var/www/ui/

# Config & entrypoint (normalize CRLF -> LF to avoid bash\r)
COPY nginx.conf   /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

# Services list must match your jar name prefixes
ENV SERVICE_LIST="eureka-server config-server api-gateway resource-allocation-service master-resource-service project-sow-service reporting-integration-service user-mgmt-service"
ENV JAVA_OPTS="-Xms128m -Xmx768m"

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
