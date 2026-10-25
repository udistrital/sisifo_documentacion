# SonarQube con Docker en Windows: análisis y reportes

Guía para Windows con Docker Desktop, backend WSL 2 y contenedores Linux. Los comandos se ejecutan en PowerShell salvo donde se indique otra cosa. Cada proyecto debe tener un `sonar-project.properties` con una clave `sonar.projectKey` única.

## 1. Instalar WSL 2 y Docker Desktop

1. Comprueba que tu versión de Windows sea compatible con los [requisitos vigentes de Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/) y que la virtualización esté habilitada en BIOS/UEFI.
2. Si no tienes WSL, abre PowerShell como administrador y ejecuta:

```powershell
wsl --install
```

3. Reinicia si Windows lo solicita. Actualiza y verifica WSL:

```powershell
wsl --update
wsl --version
wsl --list --verbose
```

4. Instala [Docker Desktop para Windows](https://docs.docker.com/desktop/setup/install/windows-install/), seleccionando el backend WSL 2.
5. Abre Docker Desktop y espera a que el motor esté listo. Utiliza **Linux containers**. Si el menú ofrece **Switch to Linux containers**, selecciónalo.
6. En una nueva ventana de PowerShell, verifica:

```powershell
docker --version
docker compose version
docker info --format '{{.OSType}}'
```

El último comando debe devolver `linux`. No necesitas instalar Java ni SonarScanner en Windows: se ejecutan dentro de los contenedores.

## 2. Preparar los límites de WSL 2

Con Docker Desktop iniciado y usando WSL 2, consulta los límites del entorno que ejecuta Docker:

```powershell
wsl -d docker-desktop -u root -- sysctl vm.max_map_count fs.file-max
```

SonarQube requiere al menos `524288` para `vm.max_map_count` y `131072` para `fs.file-max`. Ejecuta solamente los ajustes cuyos valores actuales sean inferiores:

```powershell
wsl -d docker-desktop -u root -- sysctl -w vm.max_map_count=524288
wsl -d docker-desktop -u root -- sysctl -w fs.file-max=131072
```

No reduzcas valores superiores. Estos cambios pueden perderse al reiniciar WSL o Docker Desktop: vuelve a verificarlos si SonarQube falla al iniciar. Si no aparece la distribución `docker-desktop`, verifica que Docker Desktop esté iniciado y configurado con el backend WSL 2; estos comandos no corresponden a Hyper-V ni a Docker VMM.

Referencia: [límites del host Linux de SonarQube](https://docs.sonarsource.com/sonarqube-community-build/server-installation/pre-installation/linux). Aunque la máquina sea Windows, los contenedores de esta guía se ejecutan sobre Linux.

## 3. Organizar los proyectos

Descarga o copia todos los repositorios dentro de una carpeta común. Por ejemplo:

```text
C:\Proyectos\proyecto_x\
├── compose.sonar.yml
├── exportar_metricas_sonar.py
├── usuario_rol_crud\sonar-project.properties
├── plantillas_mid\sonar-project.properties
└── otros_proyectos\sonar-project.properties
```

Reemplaza la ruta de ejemplo por la ubicación real en tu equipo:

```powershell
Set-Location 'C:\Proyectos\proyecto_x'
```

Verifica qué proyectos tienen configuración:

```powershell
Get-ChildItem -Directory | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName 'sonar-project.properties')
} | Select-Object Name
```

## 4. Crear la configuración de Docker Compose

Crea `compose.sonar.yml` en la carpeta principal con el siguiente contenido. Si ya tienes este archivo con la configuración equivalente, reutilízalo.

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

Los volúmenes mantienen la base de datos y resultados. El puerto 9000 queda accesible únicamente desde tu equipo. Las etiquetas `community` y `latest` son móviles; fija versiones antes de adoptar un proceso reproducible de actualización.

Referencia: [SonarQube Community Build con Docker](https://docs.sonarsource.com/sonarqube-community-build/server-installation/from-docker-image/set-up-and-start-container).

## 5. Iniciar SonarQube

Define una contraseña propia para PostgreSQL y levanta los servicios:

```powershell
$env:SONAR_DB_PASSWORD = 'REEMPLAZA_POR_UNA_CONTRASENA_PROPIA'
docker compose -f compose.sonar.yml up -d
docker compose -f compose.sonar.yml logs -f sonarqube
```

Espera hasta que SonarQube esté operativo. Sal del seguimiento de logs con `Ctrl+C`; los contenedores seguirán activos.

Abre [http://localhost:9000](http://localhost:9000). En una instalación nueva, ingresa con usuario `admin` y contraseña `admin`. Cambia la contraseña cuando lo solicite.

## 6. Crear y cargar el token

En **My Account → Security**, crea un **User Token** con permisos para crear proyectos, ejecutar análisis y consultar sus resultados.

Para cargarlo en PowerShell sin mostrarlo ni escribirlo literalmente en el historial:

```powershell
$tokenSeguro = Read-Host 'Pega tu token de SonarQube' -AsSecureString
$env:SONAR_TOKEN = [System.Net.NetworkCredential]::new('', $tokenSeguro).Password
Remove-Variable tokenSeguro
```

La variable de entorno contiene el token para los procesos de esta sesión. No lo guardes en archivos del repositorio. Cárgalo nuevamente al abrir otra terminal.

## 7. Analizar un proyecto

Desde la carpeta principal:

```powershell
$proyecto = (Resolve-Path '.\usuario_rol_crud').Path
$scannerArgs = @(
    'run', '--rm',
    '--network', 'x-sonar-net',
    '-e', 'SONAR_TOKEN',
    '-e', 'SONAR_USER_HOME=/tmp/sonar',
    '--mount', "type=bind,source=$proyecto,target=/usr/src",
    '-w', '/usr/src',
    'sonarsource/sonar-scanner-cli:latest',
    '-Dsonar.host.url=http://sonarqube:9000',
    '-Dsonar.qualitygate.wait=true',
    '-Dsonar.qualitygate.timeout=600'
)
docker @scannerArgs
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'Revisa el log: fallo técnico, tiempo agotado o Quality Gate no aprobado.'
}
```

Cambia `usuario_rol_crud` por la carpeta deseada. El montaje admite rutas con espacios. El scanner lee automáticamente su archivo `sonar-project.properties`.

Desde Docker, el servidor se llama `sonarqube`; desde Windows, usa `localhost`. No necesitas iniciar la aplicación analizada.

Un Quality Gate fallido provoca un código de salida distinto de cero aunque el análisis se haya publicado. Revisa el log antes de concluir que el análisis falló.

## 8. Analizar todos los proyectos

Ejecuta este bloque desde la carpeta principal. Busca configuraciones en las subcarpetas inmediatas y continúa si un análisis falla:

```powershell
$proyectos = @(Get-ChildItem -Directory | Where-Object {
    Test-Path -LiteralPath (Join-Path $_.FullName 'sonar-project.properties')
})
if ($proyectos.Count -eq 0) {
    throw 'No se encontraron proyectos con sonar-project.properties.'
}

foreach ($proyecto in $proyectos) {
    Write-Host "Analizando: $($proyecto.Name)"
    $scannerArgs = @(
        'run', '--rm',
        '--network', 'x-sonar-net',
        '-e', 'SONAR_TOKEN',
        '-e', 'SONAR_USER_HOME=/tmp/sonar',
        '--mount', "type=bind,source=$($proyecto.FullName),target=/usr/src",
        '-w', '/usr/src',
        'sonarsource/sonar-scanner-cli:latest',
        '-Dsonar.host.url=http://sonarqube:9000',
        '-Dsonar.qualitygate.wait=true',
        '-Dsonar.qualitygate.timeout=600'
    )
    docker @scannerArgs
    if ($LASTEXITCODE -eq 0) {
        Write-Host "OK: $($proyecto.Name)"
    } else {
        Write-Warning "Revisar log o Quality Gate: $($proyecto.Name)"
    }
}
```

Referencia: [SonarScanner CLI](https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/scanners/sonarscanner).

## 9. Consultar resultados

Abre [Projects](http://localhost:9000/projects) y selecciona un proyecto. Allí puedes consultar el resumen, Quality Gate, issues, Security Hotspots, métricas y código fuente.

Ejemplo: [usuario_rol_crud](http://localhost:9000/dashboard?id=usuario_rol_crud).

La cobertura requiere ejecutar las pruebas previamente e importar el reporte correspondiente. El scanner no ejecuta las pruebas ni calcula su cobertura por sí solo.

## 10. Exportar todas las métricas a un JSON por proyecto

Utiliza el script `exportar_metricas_sonar.py` entregado junto a esta guía. Funciona en Windows sin dependencias adicionales a Python 3.

Instala [Python para Windows](https://www.python.org/downloads/windows/) si no lo tienes y comprueba su disponibilidad:

```powershell
py -3 --version
```

Con `SONAR_TOKEN` ya cargado, y después de que SonarQube termine de procesar los análisis:

```powershell
py -3 .\exportar_metricas_sonar.py --url http://localhost:9000 --root . --output .\reportes-sonar
```

Si tu instalación ofrece `python` en lugar de `py`, comprueba que sea Python 3 y utiliza:

```powershell
python .\exportar_metricas_sonar.py --url http://localhost:9000 --root . --output .\reportes-sonar
```

Obtendrás archivos como:

```text
reportes-sonar\usuario_rol_crud-metricas.json
reportes-sonar\plantillas_mid-metricas.json
```

Cada archivo contiene las métricas disponibles del último análisis de la rama predeterminada, sus definiciones y la lista `metricsWithoutValue`. Una métrica sin dato no equivale a cero. Los reportes no incluyen el historial ni el detalle de cada issue. Las siguientes ejecuciones actualizan los archivos del mismo nombre.

El script Bash `exportar_metricas_sonar.sh` requiere un entorno Bash con `curl` y `jq`, como una distribución de usuario en WSL. No se ejecuta directamente como código PowerShell. Para este flujo de Windows, utiliza el script Python anterior.

## 11. Ejemplo de exportación con curl en PowerShell

Para consultar un conjunto concreto de métricas de un proyecto, usa `curl.exe`, evitando el alias `curl` de algunas versiones de PowerShell:

```powershell
New-Item -ItemType Directory -Force -Path '.\reportes-sonar' | Out-Null
$curlArgs = @(
    '--fail-with-body', '--silent', '--show-error',
    '-H', "Authorization: Bearer $env:SONAR_TOKEN",
    '--get', 'http://localhost:9000/api/measures/component',
    '--data-urlencode', 'component=usuario_rol_crud',
    '--data-urlencode', 'metricKeys=ncloc,complexity,duplicated_lines_density,coverage,alert_status',
    '-o', '.\reportes-sonar\usuario_rol_crud-resumen.json'
)
curl.exe @curlArgs
if ($LASTEXITCODE -ne 0) {
    Write-Warning 'Falló la consulta. Revisa la respuesta HTTP, el token y la clave del proyecto.'
}
```

Este ejemplo exporta solamente las métricas indicadas. Para todas las métricas y todos los proyectos, utiliza el paso 10. Si tu versión de `curl.exe` no reconoce `--fail-with-body`, usa `--fail`.

Consulta los endpoints de tu servidor en [Web API local](http://localhost:9000/web_api). Referencia: [API oficial](https://docs.sonarsource.com/sonarqube-community-build/extension-guide/web-api).

Community Build no incluye los reportes PDF oficiales de Enterprise y superiores. Puedes consultar el tablero y exportar métricas mediante la API. [Disponibilidad de PDF](https://docs.sonarsource.com/sonarqube-server/2025.4/user-guide/viewing-reports/pdf-reports).

## 12. Detener, reiniciar y diagnosticar

Desde la carpeta donde está `compose.sonar.yml`:

```powershell
# Detener sin eliminar resultados.
docker compose -f compose.sonar.yml stop

# Iniciar los contenedores existentes.
docker compose -f compose.sonar.yml start

# Ver estado y logs.
docker compose -f compose.sonar.yml ps
docker compose -f compose.sonar.yml logs --tail=100 sonarqube
```

En una nueva sesión, vuelve a definir `SONAR_DB_PASSWORD` con la misma contraseña original antes de utilizar Compose. Cambiar la variable no cambia la contraseña de PostgreSQL si ya se inicializó su volumen.

No ejecutes `docker compose -f compose.sonar.yml down -v` si necesitas conservar los resultados: `-v` elimina los volúmenes.

| Problema | Qué revisar |
| --- | --- |
| Docker no responde | Inicia Docker Desktop y espera a que el motor esté disponible. |
| Error de Elasticsearch por `vm.max_map_count` | Revisa los límites del paso 2 después de reiniciar WSL. |
| Puerto 9000 ocupado | Libera el puerto o cambia solamente el puerto del host, por ejemplo `127.0.0.1:9001:9000`; en navegador y exportador usa 9001. El scanner sigue usando `sonarqube:9000`. |
| HTTP 401 o 403 al exportar | Verifica token, expiración y permisos de lectura del usuario. |
| Proyecto inexistente | Ejecuta primero el análisis y verifica `sonar.projectKey`. |
| Error al montar la carpeta | Comprueba la ruta Windows y los permisos de acceso de Docker Desktop. |
| Proceso terminado por falta de memoria | Revisa los recursos disponibles para WSL 2 y cierra aplicaciones innecesarias. |

Esta guía no ejecuta instalaciones ni análisis. Los comandos de PowerShell deben ejecutarse y verificarse en el equipo Windows de destino.
