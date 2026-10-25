# Guías de trabajo para backend — Sísifo / OAS

**Fecha de consulta de fuentes:** 25 de octubre de 2026 (America/Bogota).  
**Alcance:** selección de tecnologías, contratos REST, persistencia y despliegues de microservicios.  
**Estado:** propuesta técnica de trabajo para el proyecto, basada en los lineamientos públicos de la Universidad Distrital; no constituye una nueva norma institucional aprobada.

Se distingue entre **base OAS**, que resume las fuentes institucionales, y **recomendación de esta guía**, que concreta decisiones de implementación. Los lineamientos consultados usan tanto OAS como OATI. La nomenclatura y los procedimientos existentes deben revisarse antes de modificar servicios en operación.

## 1. Frameworks y organización del backend

### 1.1. Selección por caso de uso

La base OAS organiza el backend en microservicios: los CRUD encapsulan persistencia por entidades de dominio y los MID coordinan procesos de negocio mediante los CRUD. Documenta APIs Beego, NestJS, Flask y una alternativa serverless con SAM. [Índice institucional](https://github.com/udistrital/lineamientos_oas).

| Tecnología | Uso principal recomendado en esta guía | Criterio de aplicación | Referencia OAS |
|---|---|---|---|
| **Go + Beego** | **Microservicios CRUD con PostgreSQL u otra base relacional autorizada** | Entidades relacionadas, integridad referencial y transacciones; mantener el acceso SQL dentro del CRUD | [APIs Beego](https://github.com/udistrital/lineamientos_oas#5-apis-beego-) |
| **Go + Beego** | **Microservicios MID** | Reglas de negocio y coordinación de varios CRUD; definir límites por dominio | [Generación de APIs](https://github.com/udistrital/lineamientos_oas/tree/master/generacion_de_apis) |
| **TypeScript + NestJS** | **Microservicios CRUD con MongoDB** | Documentos y estructuras variables, consultas orientadas al agregado y validación explícita del esquema | [Guía NestJS con MongoDB](https://github.com/udistrital/lineamientos_oas/blob/master/api_nest/api_nest.md) |
| Python + Flask | Servicios especializados que necesiten bibliotecas Python | Recomendación para procesamiento documental o integración especializada; justificar la excepción al stack preferido | [Guías Flask](https://github.com/udistrital/lineamientos_oas/tree/master/api_flask) |
| AWS SAM / serverless | Funciones por evento o tareas acotadas | Alternativa de despliegue, no un framework equivalente a Beego; evaluar límites, arranque y costos | [Guías serverless](https://github.com/udistrital/lineamientos_oas/tree/master/api_serverless) |

Estas preferencias no son restricciones técnicas de los frameworks: NestJS también admite bases relacionales. Antes de introducir otro stack, documentar el problema, alternativas, experiencia del equipo, operación y resultado de pruebas. [Integración de bases de datos en NestJS](https://docs.nestjs.com/techniques/database).

### 1.2. Forma de trabajo recomendada

1. Definir dominio y propietario de los datos. Un CRUD puede gestionar varias entidades coherentes; evitar un servicio por tabla sin justificación.
2. Diseñar primero el contrato OpenAPI: recursos, DTO, validaciones, permisos, errores y paginación.
3. En Beego, separar routers/controladores, servicios de aplicación y acceso a datos. En NestJS, organizar módulos por dominio con controladores, servicios y modelos/repositorios; el controlador traduce HTTP, no concentra SQL ni reglas complejas.
4. Mantener las consultas especializadas en el CRUD propietario. El MID consume sus contratos; no accede directamente a bases ajenas ni reconstruye consultas mediante cientos de llamadas por registro.
5. Aplicar transacciones locales a operaciones que deban ser atómicas. Para varios servicios, diseñar reintentos acotados, idempotencia y compensaciones; una transacción local no cubre llamadas HTTP externas.
6. Registrar errores con identificador de correlación, duración y servicio dependiente. Definir timeouts y limitar concurrencia; evitar registrar tokens o datos sensibles.
7. Entregar pruebas de reglas de negocio, integración con la base real de pruebas, contrato y humo. Para consultas costosas, entregar además su plan de ejecución y evidencia de carga.

## 2. Nombres de endpoints y contrato REST

### 2.1. Convención de recursos

**Base OAS:** español sin tildes ni `ñ`, minúsculas, términos comprensibles, guiones para palabras compuestas, sin `_`, extensiones ni `/` final. Usar `/` para jerarquías y mantener coherencia singular/plural; la fuente indica que el plural es habitual. Esta guía adopta **colecciones en plural** para endpoints nuevos. No incluir operaciones CRUD en la URI. [Sección 13](https://github.com/udistrital/lineamientos_oas#13-definici%C3%B3n-de-endpoints-para-apis-rest), [reglas detalladas](https://github.com/udistrital/lineamientos_oas/blob/master/generacion_de_apis/lineamientos-endpoints.md).

Patrón ilustrativo: `https://{host}/v1/{contexto}/{recursos}/{id}`. El gateway puede añadir el nombre del servicio; acordar el prefijo público para no duplicar segmentos de versión.

| Necesidad | Evitar | Método y endpoint recomendado |
|---|---|---|
| Crear auditoría | `/crear_auditoria` | `POST /v1/auditorias` |
| Listar auditorías | `/traer-auditorias` | `GET /v1/auditorias` |
| Consultar una | `/auditorias/consultar/42` | `GET /v1/auditorias/42` |
| Sustituir representación editable | `/actualizar-auditoria/42` | `PUT /v1/auditorias/42` |
| Cambiar algunos campos | `/auditorias/42/cambiar` | `PATCH /v1/auditorias/42` |
| Inactivar registro | `/eliminar-auditoria/42` | `DELETE /v1/auditorias/42`, con borrado lógico documentado |
| Listar recursos dependientes | `/traer-hallazgos/42` | `GET /v1/auditorias/42/hallazgos` |
| Crear una aprobación | `/aprobar-auditoria/42` | `POST /v1/auditorias/42/aprobaciones` |
| Filtrar y paginar | `/auditorias/vigencia/2026/pagina/1` | `GET /v1/auditorias?vigencia=2026&pagina=1&limite=20` |
| Recurso compuesto | `/planes_anuales.json` | `GET /v1/planes-anuales` |

**Recomendación de implementación:** los nombres externos no tienen que replicar tablas o colecciones. Mapear, por ejemplo, `/planes-anuales` al modelo `plan_anual`. La convención de guiones corresponde a los segmentos de recurso; definir los parámetros y campos del contrato por separado. Limitar tamaño de página y permitir únicamente filtros y órdenes conocidos; nunca aceptar SQL o un pipeline Mongo arbitrario del cliente.

### 2.2. Métodos, respuestas y compatibilidad

| Método / situación | Contrato recomendado |
|---|---|
| `GET` de colección | `200`; colección vacía devuelve `[]` o el sobre paginado acordado con lista vacía |
| `GET` de recurso inexistente | `404` |
| `POST` que crea | `201` y `Location`; usar `202` si solo se acepta una tarea asíncrona y ofrecer consulta de estado |
| `PUT` | Sustitución de campos editables; idempotente. Acordar si admite creación o responde `404` |
| `PATCH` | Actualización parcial con DTO y formato documentados; no asumir idempotencia para toda operación |
| `DELETE` | Inactivación lógica, preservando trazabilidad; `204` sin cuerpo al completarse |
| Entrada inválida / conflicto | `400` para formato o validación; `409` para conflicto con el estado actual |
| Autenticación / autorización | `401` si faltan credenciales válidas; `403` si no tiene permiso |
| Fallo interno | `500` con mensaje controlado y correlación; sin SQL, secretos ni stack trace |

La OAS exige borrado lógico en CRUD por auditoría. El `DELETE` del contrato no autoriza eliminación física. Definir además el comportamiento de consultas a registros inactivos y de solicitudes repetidas. La tabla concreta códigos recomendados; la fuente OAS describe métodos, categorías de estado y éxito para listas vacías. [Arquitectura CRUD OAS](https://github.com/udistrital/lineamientos_oas#5-apis-beego-), [endpoints OAS](https://github.com/udistrital/lineamientos_oas/blob/master/generacion_de_apis/lineamientos-endpoints.md).

En servicios existentes, conservar rutas y formatos consumidos hasta una migración explícita. Renombrar `tipo_documento` a `tipos-documento` puede romper clientes: ofrecer transición o una nueva versión mayor del contrato. La versión de ruta (`v1`) representa compatibilidad de API y no tiene que cambiar con cada release del servicio (`1.8.2`). Documentar autorización por recurso, errores y ejemplos en OpenAPI.

## 3. Bases de datos y documentación institucional

Esta selección cubre las bases documentadas para estos microservicios; no pretende inventariar todos los sistemas históricos de la Universidad.

| Motor | Uso recomendado | Lineamientos institucionales |
|---|---|---|
| **PostgreSQL** | Datos relacionados, restricciones y transacciones; CRUD Beego | [Modelos relacionales](https://github.com/udistrital/lineamientos_oas/blob/master/modelo_de_datos/lineamientos_modelos_relacionales.md) |
| **MongoDB** | Agregados documentales y esquemas flexibles controlados; CRUD NestJS | [Modelos Mongo](https://github.com/udistrital/lineamientos_oas/blob/master/modelo_de_datos/lineamientos_mongo.md), [NestJS con Mongo](https://github.com/udistrital/lineamientos_oas/blob/master/api_nest/api_nest.md) |

### 3.1. PostgreSQL

**Base OAS:** contempla `academica`, `administrativa`, `core` y `financiera`, con esquemas por funcionalidad, no por aplicación. Tablas y columnas en singular con `_`; identificador `id`, referencias terminadas en `_id` y campos `activo`, `fecha_creacion`, `fecha_modificacion`. Define convenciones para restricciones e índices y precisión para moneda y porcentaje. La ubicación de un modelo nuevo debe coordinarse con Arquitectura/DBA; la lista no ordena crear cuatro bases por microservicio. [Modelo relacional OAS](https://github.com/udistrital/lineamientos_oas/blob/master/modelo_de_datos/lineamientos_modelos_relacionales.md).

**Recomendación:** versionar migraciones, documentar restricciones e índices y conservar planes de ejecución de consultas relevantes. Elegir índices desde filtros y ordenamientos reales. Usar parámetros SQL y permisos mínimos por servicio. Un cambio de nombres de columnas se traduce en el modelo/DTO y no obliga a cambiar la URI.

### 3.2. MongoDB

**Base OAS:** nombres en español, singular y `snake_case`; propone longitud de 10 a 30 caracteres, aunque sus ejemplos y campos obligatorios incluyen nombres más cortos. Modelar según consultas frecuentes, embeber relaciones pequeñas y referenciar relaciones de mayor cardinalidad con sufijo `_id`. Para colecciones no paramétricas exige estado y fechas de auditoría; diseñar índices según consultas. Mantener campos reservados como `_id` y documentar excepciones de nomenclatura. [Modelo Mongo OAS](https://github.com/udistrital/lineamientos_oas/blob/master/modelo_de_datos/lineamientos_mongo.md).

**Aclaración técnica:** el documento institucional presenta `Date` como 32 bits y prescribe `timestamp` para fechas de aplicación. MongoDB define BSON **Date de 64 bits**, y reserva BSON Timestamp principalmente para usos internos. Se recomienda almacenar `fecha_creacion` y `fecha_modificacion` como BSON Date/ISODate y registrar esta aclaración con Arquitectura antes de alterar modelos existentes. [Tipos BSON oficiales](https://www.mongodb.com/docs/manual/reference/bson-types/).

**Recomendación:** validar DTO y esquema; esquema flexible no significa ausencia de contrato. Diseñar índices y agregaciones con evidencia de ejecución; evitar arreglos embebidos sin límite. Mongoose permite pipelines, pero no convierte automáticamente todos sus tipos: validar y convertir identificadores antes de construir agregaciones. [API de agregación Mongoose](https://mongoosejs.com/docs/api/aggregate.html).

## 4. Despliegues con GitFlow y SemVer

### 4.1. Correspondencia de ramas y ambientes

**Flujo del proyecto:** se utiliza GitFlow con `develop` como rama de integración y `master` como historial de versiones productivas. Los candidatos de `release/*` se despliegan en el ambiente de pruebas para su validación. Configurar los disparadores CI/CD conforme a esta correspondencia de ramas y ambientes. [Ramas OAS](https://github.com/udistrital/lineamientos_oas/blob/master/repositorios_institucionales/nombre_branch.md), [despliegues OAS](https://github.com/udistrital/lineamientos_oas/blob/master/despliegues/lineamientos.md).

| Rama o referencia | Nace de | Función y destino |
|---|---|---|
| `feature/<issue>-<descripcion>` | `develop` | Desarrollo de una funcionalidad; PR hacia `develop` |
| `fix/<issue>-<descripcion>` | `develop` | Corrección detectada en pruebas; integrar en el último `release/*` desplegado en ese ambiente y asegurar su incorporación en `develop` |
| `develop` | Rama de integración | Integración continua y ambiente de desarrollo |
| `release/X.Y.Z` | Commit seleccionado de `develop` | Estabilización del alcance y candidatos para el ambiente de pruebas; únicamente correcciones y preparación del release |
| `master` | Recibe PR del release validado | Historial oficial de versiones; producción despliega un artefacto identificado |
| `hotfix/X.Y.Z` | Commit de la versión productiva afectada | Corrección urgente; validar y reintegrar en `master`, `develop` y releases activos afectados |

**Flujo de correcciones del proyecto:** los arreglos encontrados en el ambiente de pruebas se desarrollan en una nueva rama creada desde `develop` (nombre sugerido: `feature/<issue>-<descripcion>`). Una vez revisados, se integran en la rama `develop` y luego la rama del último release desplegado en ese ambiente y se genera un nuevo candidato para validar.

Cuando un ajuste deba mantenerse separado de los cambios existentes en `develop`, se puede crear la nueva rama de corrección desde el último release desplegado en el ambiente de pruebas. Una vez implementado y revisado el ajuste, integrar los cambios mediante PR tanto en ese release como en `develop`, verificando que el release incorpore únicamente la corrección prevista. Generar un nuevo candidato y volver a ejecutar las pruebas después de la integración. Esta alternativa complementa el flujo habitual del proyecto sobre la referencia de [GitFlow](https://nvie.com/posts/a-successful-git-branching-model/).

### 4.2. Versionamiento semántico

Usar `MAJOR.MINOR.PATCH` por microservicio y reflejarlo en `release/X.Y.Z`, manifiesto de aplicación y release notes. El paso a producción en `master` no requiere crear tags nuevos; registrar la relación entre versión, commit y digest del artefacto desplegado. [Especificación SemVer 2.0.0](https://semver.org/lang/es/).

| Cambio de contrato público | Incremento | Ejemplo |
|---|---|---|
| Eliminar endpoint, quitar campo o cambiar un tipo de forma incompatible | MAJOR | `1.8.0` → `2.0.0` |
| Añadir funcionalidad compatible | MINOR | `1.8.0` → `1.9.0` |
| Corregir un error sin romper compatibilidad | PATCH | `1.8.0` → `1.8.1` |
| Candidato aún no liberado | Sufijo prerelease | `1.9.0-rc.1`, `1.9.0-rc.2` |

Agregar un campo obligatorio a una petición puede ser incompatible aunque sea un campo nuevo. No sobrescribir tags ni artefactos publicados: toda corrección posterior recibe nueva versión. En cambios mayores, planificar convivencia y migración de consumidores.

### 4.3. Procedimiento de publicación

1. **Preparar:** líder técnico define alcance, versión, dependencias entre servicios, cambios de configuración, migraciones, responsables, ventana y criterios de rollback. Generar y validar el Swagger actualizado de cada microservicio incluido en el despliegue, en formato **JSON conforme a OpenAPI 2.0 (Swagger 2.0)**. Debe corresponder al candidato e incluir rutas, métodos, parámetros, modelos, respuestas y seguridad. Actualizar README, changelog y `.drone.yml` según corresponda.
2. **Estabilizar:** abrir `release/X.Y.Z` desde `develop`, congelar funcionalidades y crear candidato `X.Y.Z-rc.N`. Fijar dependencias y registrar commit de origen.
3. **Validar en el ambiente de pruebas:** desplegar el candidato generado desde `release/X.Y.Z` y coordinar la revisión de Arquitectura según OAS. Ejecutar pruebas unitarias, integración, contrato, carga, funcionales y aceptación según el cambio. Para cada arreglo detectado, crear una nueva rama desde `develop`, implementar y revisar la corrección e integrarla en el último release desplegado en pruebas conforme a la sección 4.1. Generar y desplegar un nuevo candidato identificable y repetir las pruebas correspondientes.
4. **Preparar operación:** coordinar con Infraestructura configuración y pipeline, con Arquitectura registro/actualización en WSO2 y con DBA las migraciones. **Cuando se implementen nuevos endpoints, solicitar su registro al equipo de Arquitectura enviando el enlace al repositorio del microservicio y su archivo `swagger.json` actualizado en OpenAPI 2.0.** Identificar además el release o commit, ambiente y endpoints nuevos para que el registro corresponda al contrato que se desplegará. Confirmar el registro antes de validar su consumo por el gateway. El documento OAS menciona Jenkins, Drone y Tuleap; confirmar qué integraciones siguen activas en el repositorio. Registrar nombres y referencias de secretos, sin incluir valores en Git.
5. **Promover:** aprobar y fusionar el PR del release validado hacia `master`, sin requerir la creación de un tag nuevo. Asociar la versión del release y el commit resultante a un artefacto inmutable. Preferir promover el mismo `release` probado.
6. **Desplegar:** ejecutar migraciones compatibles cuando corresponda, desplegar por `release` y comprobar health checks, endpoints críticos, errores y latencia a través del gateway. Configurar el pipeline para que la promoción aprobada en `master` genere un único despliegue productivo, sin depender de la creación de tags.
7. **Cerrar y podar:** una vez culminado el despliegue en producción y finalizadas satisfactoriamente las pruebas funcionales en ese ambiente, registrar evidencias y aprobación operativa, reintegrar las correcciones del release en `develop` y podar los releases de rollback obsoletos conforme a la sección 4.4. Conservar la versión anterior recuperable. Una rama de release cerrada puede eliminarse cuando el commit de la versión permanece accesible en el historial de `master` y sus artefactos y registros de despliegue están protegidos; la recuperación no debe depender de esa rama.

El entregable para Arquitectura es el archivo JSON en OpenAPI 2.0; una URL de Swagger UI no sustituye el archivo solicitado. Si el generador del microservicio produce otra versión de OpenAPI, preparar y validar una conversión compatible antes de enviar la solicitud. Regenerar el documento cuando cambie el contrato durante la estabilización y actualizar la solicitud si afecta el registro. La versión en OpenAPI 2.0 no sobrescribe la versión generada por el framework.

La OAS exige Swagger actualizado, configuración de despliegue y resultados de pruebas antes de producción; asigna revisión a Arquitectura y cambios de base a DBA. Las medidas sobre digest, promoción y retención son recomendaciones operativas de esta guía. [Procedimiento institucional](https://github.com/udistrital/lineamientos_oas/blob/master/despliegues/lineamientos.md).

El formato OpenAPI 2.0, el envío de repositorio y Swagger JSON a Arquitectura y la poda posterior a las pruebas funcionales se incorporan como instrucciones de trabajo del proyecto.

### 4.4. Conservación de releases y rollback

**Política propuesta:** conservar como mínimo el release productivo actual **N** y el último release estable anterior **N−1**, completos y protegidos contra limpieza automática. Mantener N−1 durante toda la permanencia de N y hasta que otra versión estable lo sustituya como respaldo. Si existen consumidores o migraciones que requieran más historia, ampliar la retención.

**Poda después del despliegue:** al completar satisfactoriamente el despliegue productivo y sus pruebas funcionales, actualizar el inventario de versiones y retirar los releases de rollback obsoletos, normalmente **N−2 y anteriores**, salvo una retención justificada. Antes de podar, comprobar que N y N−1 conservan los elementos de la tabla siguiente y que N−1 sigue siendo recuperable. Retirar ramas cerradas y artefactos operativos redundantes según la política de retención, preservando los commits de las versiones, los tags existentes, las notas y las evidencias de auditoría. Registrar qué se eliminó y cuáles versiones permanecen disponibles. No ejecutar la poda si las pruebas funcionales fallan o hay un rollback pendiente.

Por ejemplo, después de desplegar y validar `1.9.0`, conservar `1.9.0` y el release estable anterior `1.8.2`; los respaldos operativos de versiones más antiguas pueden podarse si no tienen una retención justificada.

**Antes de desplegar N:** evaluar y probar la compatibilidad de N−1 con el esquema y los datos que quedarán después de la migración. Si se identifican incompatibilidades, **no modificar el release N−1**: conservar su código y artefacto originales, documentar las afectaciones sobre datos, servicios y consumidores, y definir con Arquitectura y DBA el procedimiento necesario para el rollback (de ser necesario). Este procedimiento debe indicar cómo recuperar un esquema y datos compatibles con N−1, los respaldos requeridos, el tratamiento de las operaciones registradas durante N, la posible pérdida de datos, los tiempos de recuperación y los responsables. Validar el procedimiento en el ambiente de pruebas antes del despliegue; no asumir que basta con redesplegar N−1. Cuando sea viable, diseñar las migraciones de N mediante *expandir–migrar–contraer* para preservar la compatibilidad y posponer la eliminación de estructuras hasta que termine la ventana de retorno.

**Secuencia de rollback propuesta:**

1. El responsable operativo activa el retorno al cumplirse criterios acordados: fallos en procesos críticos, aumento de errores o incumplimiento sostenido del SLO. Detener la promoción y controlar escrituras si hay riesgo de inconsistencia.
2. Verificar disponibilidad de imagen, configuración, secretos, gateway y compatibilidad de datos de N−1. Si la compatibilidad no existe, ejecutar el plan de recuperación de datos previamente aprobado con DBA o aplicar una corrección hacia adelante; no lanzar una migración inversa a ciegas.
3. Redesplegar **el release conservado de N−1** y su configuración compatible. No reconstruir desde la rama ni reescribir el historial de `master`.
4. Verificar salud, autenticación, consultas, escritura controlada y proceso crítico por el gateway; observar métricas durante la ventana acordada.
5. Registrar versión retirada, versión restaurada, causa, tiempo e impacto. Mantener la evidencia del release fallido y crear una nueva versión corregida, superior a las ya publicadas.

Un rollback de aplicación no revierte datos escritos durante N. Restaurar un backup puede perder operaciones posteriores; acordar RPO/RTO, respaldo y recuperación con DBA. Ensayar el retorno en el ambiente de pruebas antes de liberar cambios de esquema o contratos.

### 4.5. Criterio de entrega de un backend

- [ ] Stack y modelo de datos justificados por el dominio.
- [ ] Contrato OpenAPI, endpoints, validaciones y permisos revisados.
- [ ] Swagger JSON actualizado y validado en OpenAPI 2.0 por cada microservicio del despliegue; ante nuevos endpoints, solicitud a Arquitectura con repositorio y archivo `swagger.json`, y registro confirmado.
- [ ] Consultas parametrizadas o pipelines controlados; índices y paginación verificados.
- [ ] Pruebas relevantes y evidencia de carga cuando corresponda.
- [ ] Release SemVer trazables; el paso a producción no requiere un tag nuevo.
- [ ] Configuración, gateway y migraciones coordinados con sus responsables.
- [ ] N y N−1 disponibles; compatibilidad y procedimiento de rollback probados.
- [ ] Despliegue productivo y pruebas funcionales culminados satisfactoriamente; poda de releases de rollback obsoletos ejecutada y registrada, conservando N y N−1.

### 4.6. Nota sobre la identificación del release de rollback

**N−1 identifica el último release estable que pasó a producción antes del release N que se está preparando o desplegando.** Pueden existir releases posteriores a N−1 en desarrollo o pruebas, incluso con números de versión mayores, pero no deben confundirse con el respaldo de rollback: esa condición depende del historial de despliegues productivos, no del orden de creación de ramas ni de la numeración. Una vez publicado N, N−1 sigue siendo su respaldo anterior; para el siguiente despliegue, la referencia se actualiza tomando como respaldo el último release productivo estable.

Para evitar confusiones, se pueden podar las ramas de releases intermedios que ya no sean necesarias y mantener una única rama de release N en preparación, conservando siempre el código, artefacto y referencias recuperables de N−1. Esta poda no implica eliminar el respaldo productivo anterior.

Como alternativa de identificación, se recomienda el distintivo **`X.Y.Z.prod`** para un release opcional asociado del release que pasó a producción; por ejemplo, `1.8.2.prod`. Si ya existe `v1.8.2`, se puede añadir `1.8.2.prod` sobre el mismo release. El sufijo `prod` distingue el despliegue productivo y mantiene reconocible la versión `1.8.2`. Este distintivo es opcional y no convierte la creación de release o tags en un requisito para publicar en `master`.

## 5. Fuentes consultadas

Todas consultadas el **25 de octubre de 2026**. Los enlaces institucionales a `master` pueden cambiar. Los documentos relacional, Mongo y NestJS se verificaron además mediante sus archivos públicos raw.

| Fuente | Aporte / alcance |
|---|---|
| [Índice OAS/OATI](https://github.com/udistrital/lineamientos_oas) | Arquitectura, CRUD/MID y tecnologías documentadas |
| [Endpoints OAS](https://github.com/udistrital/lineamientos_oas/blob/master/generacion_de_apis/lineamientos-endpoints.md) | Nomenclatura REST y semántica general |
| [Modelos relacionales OAS](https://github.com/udistrital/lineamientos_oas/blob/master/modelo_de_datos/lineamientos_modelos_relacionales.md) | PostgreSQL, esquemas, campos y restricciones |
| [Modelos Mongo OAS](https://github.com/udistrital/lineamientos_oas/blob/master/modelo_de_datos/lineamientos_mongo.md) | Documentos, referencias, auditoría e índices |
| [NestJS OAS](https://github.com/udistrital/lineamientos_oas/blob/master/api_nest/api_nest.md) | Generación de APIs para MongoDB |
| [Ramas OAS](https://github.com/udistrital/lineamientos_oas/blob/master/repositorios_institucionales/nombre_branch.md) | Adopción institucional de GitFlow |
| [Despliegues OAS](https://github.com/udistrital/lineamientos_oas/blob/master/despliegues/lineamientos.md) | Ambientes, requisitos y responsables |
| [NestJS: bases de datos](https://docs.nestjs.com/techniques/database) | Integraciones de persistencia |
| [Mongoose: Aggregate](https://mongoosejs.com/docs/api/aggregate.html) | Consultas especializadas y conversión de tipos |
| [MongoDB: tipos BSON](https://www.mongodb.com/docs/manual/reference/bson-types/) | Aclaración de Date y Timestamp |
| [SemVer 2.0.0](https://semver.org/lang/es/) | Versiones, compatibilidad y prereleases |
| [GitFlow original](https://nvie.com/posts/a-successful-git-branching-model/) | Ciclo de feature, release y hotfix |
