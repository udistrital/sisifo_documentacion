#!/bin/bash

docker run --rm \
  --network sisifo-sonar-net \
  --user "$(id -u):$(id -g)" \
  -e SONAR_TOKEN \
  -e SONAR_USER_HOME=/tmp/sonar \
  -v "$PWD/usuario_rol_crud:/usr/src" \
  -w /usr/src \
  sonarsource/sonar-scanner-cli:latest \
  -Dsonar.host.url=http://sonarqube:9000 \
  -Dsonar.qualitygate.wait=true \
  -Dsonar.qualitygate.timeout=600
