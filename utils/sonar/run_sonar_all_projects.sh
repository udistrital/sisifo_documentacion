for config in "$PWD"/*/sonar-project.properties; do
  [ -f "$config" ] || continue
  proyecto="${config%/sonar-project.properties}"

  printf '\nAnalizando: %s\n' "${proyecto##*/}"

  if docker run --rm \
    --network sisifo-sonar-net \
    --user "$(id -u):$(id -g)" \
    -e SONAR_TOKEN \
    -e SONAR_USER_HOME=/tmp/sonar \
    -v "$proyecto:/usr/src" \
    -w /usr/src \
    sonarsource/sonar-scanner-cli:latest \
    -Dsonar.host.url=http://sonarqube:9000 \
    -Dsonar.qualitygate.wait=true \
    -Dsonar.qualitygate.timeout=600
  then
    printf 'Análisis y Quality Gate correctos: %s\n' "${proyecto##*/}"
  else
    printf 'Revisar log o Quality Gate: %s\n' "${proyecto##*/}"
  fi
done
