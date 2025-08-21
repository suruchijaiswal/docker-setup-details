# docker-setup (single image)
Builds one image that runs all microservices + two React UIs under nginx.

## Put these four zips beside this Dockerfile before building
- rma_java_microservices.zip
- api-gateway-main.zip
- rma_react_frontend-main.zip
- rms_react_frontend-main.zip

## Build
docker build -t rma-one:v2 .

## Run (needs Postgres reachable at POSTGRES_HOST:POSTGRES_PORT)
docker run --rm -p 80:80 --env-file .env rma-one:v2

## Azure App Service
Push image to a registry and set app settings:
WEBSITES_PORT=80 and the DB/JWT vars from .env
