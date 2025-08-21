#!/usr/bin/env bash
set -euo pipefail

SUP_CONF_DIR="/etc/supervisor/conf.d"
SERVICES_DIR="/app/services"

rm -f "${SUP_CONF_DIR}/services.conf"
touch "${SUP_CONF_DIR}/services.conf"

cat >> "${SUP_CONF_DIR}/services.conf" <<'NGINX_EOF'
[program:nginx]
command=/usr/sbin/nginx -g 'daemon off;'
autorestart=true
priority=5
stdout_logfile=/var/log/supervisor/nginx.stdout.log
stderr_logfile=/var/log/supervisor/nginx.stderr.log
NGINX_EOF

sanitize() { echo "$1" | tr '-' '_' | tr '[:upper:]' '[:lower:]'; }

for NAME in ${SERVICE_LIST}; do
  JAR_PATH="$(ls -1 ${SERVICES_DIR}/${NAME}*.jar 2>/dev/null | head -n1 || true)"
  if [[ -z "${JAR_PATH}" ]]; then
    echo "WARNING: No JAR found for ${NAME}"
    continue
  fi

  SAFE="$(sanitize "${NAME}")"
  VAR="JAVA_OPTS__${SAFE}"
  SERVICE_JAVA_OPTS="${!VAR:-$JAVA_OPTS}"

  case "${NAME}" in
    eureka-server) PORT=8761 ;;
    api-gateway) PORT=8080 ;;
    user-mgmt-service) PORT=8081 ;;
    project-sow-service) PORT=8082 ;;
    resource-allocation-service) PORT=8083 ;;
    reporting-integration-service) PORT=8084 ;;
    master-resource-service) PORT=8085 ;;
    config-server) PORT=8888 ;;
    *) PORT=0 ;;
  esac

  DBNAME=""
  case "${NAME}" in
    user-mgmt-service) DBNAME="${USER_MGMT_DB:-}" ;;
    project-sow-service) DBNAME="${PROJECT_SOW_DB:-}" ;;
    resource-allocation-service) DBNAME="${RESOURCE_ALLOCATION_DB:-}" ;;
    master-resource-service) DBNAME="${MASTER_SERVICE_DB:-}" ;;
    api-gateway) DBNAME="${API_GATEWAY_DB:-}" ;;
  esac

  {
    echo "[program:${NAME}]"
    if [[ -n "${DBNAME}" ]]; then
      echo "command=/bin/bash -lc 'exec env SERVER_PORT=${PORT} SPRING_DATASOURCE_URL=jdbc:postgresql://${POSTGRES_HOST}:${POSTGRES_PORT}/${DBNAME} java ${SERVICE_JAVA_OPTS} -jar \"${JAR_PATH}\"'"
    else
      echo "command=/bin/bash -lc 'exec env SERVER_PORT=${PORT} java ${SERVICE_JAVA_OPTS} -jar \"${JAR_PATH}\"'"
    fi
    echo "directory=/app/services"
    echo "autorestart=true"
    echo "stdout_logfile=/var/log/supervisor/${NAME}.stdout.log"
    echo "stderr_logfile=/var/log/supervisor/${NAME}.stderr.log"
    echo "environment=POSTGRES_HOST=\"${POSTGRES_HOST}\",POSTGRES_PORT=\"${POSTGRES_PORT}\",POSTGRES_USER=\"${POSTGRES_USER}\",POSTGRES_PASSWORD=\"${POSTGRES_PASSWORD}\",JWT_SECRET=\"${JWT_SECRET}\",APP_JWT_SECRET=\"${JWT_SECRET}\",EUREKA_CLIENT_SERVICEURL_DEFAULTZONE=\"http://localhost:8761/eureka/\""
    echo
  } >> "${SUP_CONF_DIR}/services.conf"
done

exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf -n
