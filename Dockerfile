# ==== Build Spring Boot jars ====
FROM maven:3.9-eclipse-temurin-21 AS builder-java
RUN apt-get update && apt-get install -y --no-install-recommends unzip && rm -rf /var/lib/apt/lists/*
WORKDIR /src

COPY rma_java_microservices.zip /src/
COPY api-gateway-main.zip /src/

RUN unzip -q rma_java_microservices.zip -d rma_java_microservices && \
    unzip -q api-gateway-main.zip -d api-gateway-main

# Build all Maven modules (skip tests)
RUN set -eux; \
    find /src -name "pom.xml" -maxdepth 4 | sort -u > /tmp/poms.txt; \
    while read -r P; do mvn -q -DskipTests -f "$P" clean package; done < /tmp/poms.txt; \
    mkdir -p /out/jars && \
    find /src -type f -path "*/target/*" -name "*.jar" -exec cp {} /out/jars/ \;

# ==== Build React app (auto-detect) ====
FROM node:20-alpine AS builder-react
RUN apk add --no-cache unzip
WORKDIR /ui

COPY rma_react_frontend-main.zip /ui/

# Unzip and detect app dir (first top-level dir)
RUN unzip -q rma_react_frontend-main.zip -d rma && \
    set -eux; APPDIR="$(find /ui/rma -maxdepth 1 -mindepth 1 -type d | head -n1)"; \
    cd "$APPDIR"; \
    # install deps (prefer lockfile if present)
    if [ -f yarn.lock ]; then corepack enable || true; yarn install --frozen-lockfile || yarn install; \
    else npm ci || npm install; fi; \
    # determine build command
    if npm run -s | grep -q '^  build'; then \
      npm run build; \
    elif grep -q '"next"' package.json; then \
      npx --yes next build && npx --yes next export -o build; \
    elif grep -q '"vite"' package.json; then \
      npx --yes vite build; \
    elif grep -q '"react-scripts"' package.json; then \
      npx --yes react-scripts build; \
    elif grep -q '"@angular/cli"' package.json; then \
      (npm run build || npx --yes ng build --configuration production --output-path build); \
    else \
      echo "No build script found; creating a minimal static build"; \
      mkdir -p build && printf '<!doctype html><meta charset=utf-8><title>App</title><h1>UI build not provided</h1>' > build/index.html; \
    fi; \
    # normalize output to /out/ui-root/build (accept common folders)
    mkdir -p /out/ui-root && \
    if [ -d build ]; then cp -r build /out/ui-root/; \
    elif [ -d dist ]; then cp -r dist /out/ui-root/build; \
    elif [ -d out ];  then cp -r out  /out/ui-root/build; \
    else cp -r . /out/ui-root/build; fi

# ==== Final runtime ====
FROM eclipse-temurin:21-jre

RUN apt-get update && apt-get install -y --no-install-recommends supervisor nginx ca-certificates && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/services /var/log/supervisor /var/www/ui

COPY --from=builder-java  /out/jars          /app/services/
COPY --from=builder-react /out/ui-root/build /var/www/ui/

COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# services to run inside the single container
ENV SERVICE_LIST="eureka-server config-server api-gateway resource-allocation-service master-resource-service project-sow-service reporting-integration-service user-mgmt-service"
ENV JAVA_OPTS="-Xms128m -Xmx768m"

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]
