# SonarQube con Docker: configuración, análisis y reportes

Esta guía permite levantar un servidor local de SonarQube Community Build y analizar por separado los proyectos de esta carpeta usando sus archivos `sonar-project.properties`.

## 1. Proyectos configurados

Realiza la descarga de los proyectos que se analizaran en la misma carpeta.

Cada uno tiene un `sonar.projectKey` diferente, por lo que aparecerá como un proyecto independiente en SonarQube.

## 2. Verificar Docker y preparar Linux

Comprueba que Docker y Docker Compose estén instalados y que puedas acceder al servicio:

```bash
docker --version
docker compose version
docker info
```

SonarQube utiliza Elasticsearch. Comprueba los límites del host:

```bash
sysctl vm.max_map_count fs.file-max
```

Los mínimos son `524288` para `vm.max_map_count` y `131072` para `fs.file-max`. Ejecuta únicamente el ajuste cuyo valor actual sea inferior:

```bash
sudo sysctl -w vm.max_map_count=524288
sudo sysctl -w fs.file-max=131072
```

No reduzcas valores que ya sean superiores. Para conservar los ajustes después de reiniciar, agrega los valores necesarios en `/etc/sysctl.d/99-sonarqube.conf` y aplica la configuración con `sudo sysctl --system`.

Referencia: [requisitos oficiales para Linux](https://docs.sonarsource.com/sonarqube-community-build/server-installation/pre-installation/linux).

## 3. Crear el archivo de Docker Compose

Ubícate en la carpeta principal:

```bash
cd "/{path}/proyecto_x"
```

Crea un archivo llamado `compose.sonar.yml` con este contenido:

```yaml
name: x-sonar

services:
  db:
    image: postgres:17
    environment:
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: ${SONAR_DB_PASSWORD:?Define SONAR_DB_PASSWORD}
      POSTGRES_DB: sonar
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U sonar -d sonar"]
      interval: 10s
      timeout: 5s
      retries: 10
    restart: unless-stopped

  sonarqube:
    image: sonarqube:community
    depends_on:
      db:
        condition: service_healthy
    ports:
      - "127.0.0.1:9000:9000"
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://db:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: ${SONAR_DB_PASSWORD:?Define SONAR_DB_PASSWORD}
    volumes:
      - sonar_data:/opt/sonarqube/data
      - sonar_extensions:/opt/sonarqube/extensions
      - sonar_logs:/opt/sonarqube/logs
    ulimits:
      nofile:
        soft: 131072
        hard: 131072
      nproc: 8192
    restart: unless-stopped

networks:
  default:
    name: x-sonar-net

volumes:
  postgres_data:
  sonar_data:
  sonar_extensions:
  sonar_logs:
```

Los volúmenes conservan la base de datos y los resultados entre reinicios. El puerto se publica únicamente en la máquina local.

PostgreSQL 17 está dentro de las versiones compatibles documentadas. Las etiquetas `community` y `latest` usadas en esta guía son móviles; para una instalación reproducible, fija las versiones utilizadas antes de futuras actualizaciones.

Referencias: [instalación con Docker](https://docs.sonarsource.com/sonarqube-community-build/server-installation/from-docker-image/set-up-and-start-container) y [bases de datos compatibles](https://docs.sonarsource.com/sonarqube-community-build/server-installation/installing-the-database).

## 4. Iniciar SonarQube

Define una contraseña propia para la base de datos y levanta los servicios:

```bash
export SONAR_DB_PASSWORD='REEMPLAZA_POR_UNA_CONTRASENA_PROPIA'

docker compose -f compose.sonar.yml up -d
docker compose -f compose.sonar.yml logs -f sonarqube
```

Espera hasta que el log indique que SonarQube está operativo. Sal de los logs con `Ctrl+C`; los contenedores seguirán funcionando.

Abre [SonarQube local](http://localhost:9000). En una instalación nueva, las credenciales iniciales son:

- Usuario: `admin`
- Contraseña: `admin`

Cambia la contraseña cuando lo solicite.

## 5. Crear y cargar el token

En SonarQube, entra en **My Account → Security** y genera un token de tipo **User Token**. El usuario debe tener permisos para crear proyectos, ejecutar análisis y consultar sus resultados.

En tu terminal `zsh`, introduce el token sin mostrarlo ni escribirlo en el historial:

```zsh
read -rs 'SONAR_TOKEN?Pega tu token de SonarQube: '
echo
export SONAR_TOKEN
```

Si utilizas Bash, el equivalente es:

```bash
read -rsp 'Pega tu token de SonarQube: ' SONAR_TOKEN
echo
export SONAR_TOKEN
```

El token servirá para analizar los proyectos y consultar la API. No lo agregues a los archivos del repositorio. Debes cargarlo nuevamente si abres otra terminal.

Referencia: [gestión de tokens](https://docs.sonarsource.com/sonarqube-community-build/user-guide/managing-tokens).

## 6. Analizar un proyecto

Desde la carpeta principal, ejecuta:

```bash
docker run --rm \
  --network x-sonar-net \
  --user "$(id -u):$(id -g)" \
  -e SONAR_TOKEN \
  -e SONAR_USER_HOME=/tmp/sonar \
  -v "$PWD/usuario_rol_crud:/usr/src" \
  -w /usr/src \
  sonarsource/sonar-scanner-cli:latest \
  -Dsonar.host.url=http://sonarqube:9000 \
  -Dsonar.qualitygate.wait=true \
  -Dsonar.qualitygate.timeout=600
```

Para analizar otro proyecto, cambia `usuario_rol_crud` por el nombre de su carpeta.

El scanner lee automáticamente `/usr/src/sonar-project.properties`. Dentro de la red Docker, accede al servidor mediante `http://sonarqube:9000`; desde el navegador se utiliza `http://localhost:9000`.

No es necesario levantar las aplicaciones para ejecutar el análisis estático. El usuario que ejecuta Docker debe poder leer el código y escribir el directorio de trabajo del scanner en la carpeta montada.

La opción `sonar.qualitygate.wait=true` espera hasta que el servidor procese el resultado. Si el Quality Gate falla, el comando termina con error aunque el análisis se haya publicado correctamente. Revisa el log para distinguir un incumplimiento de calidad de un fallo técnico o un tiempo de espera agotado.

Referencias: [SonarScanner CLI en Docker](https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/scanners/sonarscanner) y [parámetros del Quality Gate](https://docs.sonarsource.com/sonarqube-server/2025.1/analyzing-source-code/analysis-parameters).

## 7. Analizar todos los proyectos configurados

Desde la carpeta principal, ejecuta:

```bash
for config in "$PWD"/*/sonar-project.properties; do
  [ -f "$config" ] || continue
  proyecto="${config%/sonar-project.properties}"

  printf '\nAnalizando: %s\n' "${proyecto##*/}"

  if docker run --rm \
    --network x-sonar-net \
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
```

El ciclo analiza los proyectos uno tras otro y continúa si alguno falla. Busca archivos en las subcarpetas inmediatas de la carpeta principal.

## 8. Consultar el reporte en el navegador

Abre [Projects](http://localhost:9000/projects) y selecciona un proyecto:

| Sección | Contenido |
| --- | --- |
| Overview | Estado general y Quality Gate. |
| Issues | Hallazgos con archivo, línea y explicación. |
| Security Hotspots | Puntos que requieren revisión de seguridad. |
| Measures | Métricas de código, duplicación y cobertura. |
| Code | Hallazgos sobre el código fuente. |

Ejemplo: [reporte de usuario_rol_crud](http://localhost:9000/dashboard?id=usuario_rol_crud).

## 9. Exportar métricas como JSON

Después de finalizar el procesamiento del análisis, ejecuta desde la carpeta principal:

```bash
mkdir -p reportes-sonar

curl --fail-with-body --silent --show-error \
  -H "Authorization: Bearer $SONAR_TOKEN" \
  --get "http://localhost:9000/api/measures/component" \
  --data-urlencode "component=usuario_rol_crud" \
  --data-urlencode "metricKeys=ncloc,complexity,duplicated_lines_density,coverage,alert_status" \
  -o reportes-sonar/usuario_rol_crud-metricas.json
```

Este archivo contiene las métricas solicitadas disponibles para el proyecto; no es una exportación de todos los hallazgos. Para otros proyectos, cambia `component` por su `sonar.projectKey` y ajusta el nombre del archivo de salida.

La documentación de endpoints de la versión instalada está en [Web API local](http://localhost:9000/web_api). Puedes utilizarla para consultar otras métricas y hallazgos; los endpoints de listas pueden requerir paginación.

Community Build no incluye la exportación oficial de reportes PDF, disponible en Enterprise y superiores. Con Community puedes consultar el tablero y extraer datos por API.

Referencias: [Web API](https://docs.sonarsource.com/sonarqube-community-build/extension-guide/web-api) y [disponibilidad de reportes PDF](https://docs.sonarsource.com/sonarqube-server/2025.4/user-guide/viewing-reports/pdf-reports).

## 10. Cobertura de pruebas

Los seis archivos revisados no configuran importación de cobertura. El scanner no ejecuta las pruebas: para obtener cobertura debes ejecutarlas previamente y configurar la ruta del reporte correspondiente al lenguaje y a la herramienta de pruebas.

La configuración de archivos de prueba mediante `sonar.tests` o `sonar.test.inclusions` no sustituye un reporte de cobertura. Sin su importación, el resultado no representa la cobertura real de tus pruebas.

## 11. Repetir análisis y administrar los contenedores

Después de cambiar código, repite el paso 6 o 7. SonarQube actualizará cada proyecto usando su misma clave.

Para detener los servicios:

```bash
docker compose -f compose.sonar.yml stop
```

Para iniciar nuevamente los contenedores existentes:

```bash
docker compose -f compose.sonar.yml start
```

Para consultar el estado y los logs:

```bash
docker compose -f compose.sonar.yml ps
docker compose -f compose.sonar.yml logs --tail=100 sonarqube
```

Mantén disponible `SONAR_DB_PASSWORD` al ejecutar Compose. En una terminal nueva, vuelve a exportar la misma contraseña usada al inicializar PostgreSQL. Cambiar únicamente la variable no modifica la contraseña de una base de datos ya inicializada.

No ejecutes `docker compose -f compose.sonar.yml down -v` si quieres conservar los resultados: la opción `-v` elimina los volúmenes.

Esta guía documenta los pasos; su creación no inicia contenedores ni ejecuta análisis.
