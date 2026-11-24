# Configuración de Jenkins como código — `orders-ci`

## Objetivo

Jenkins corriendo en un contenedor Docker local, configurado como código (JCasC + Job DSL), con un job de tipo **Pipeline** que monitoréa la rama `master` de <https://github.com/Velasquez076/orders-ci> y ejecuta el `Jenkinsfile` de la raíz del repositorio.

- **Job:** `integracion-continua-backend-orders-ci`
- **Repo:** `https://github.com/Velasquez076/orders-ci` (público)
- **Rama:** `master`
- **Script:** `Jenkinsfile`
- **Trigger inicial:** `pollSCM` con cron `H/2 * * * *` (cada ~2 min)
- **Resultado final:** build **#4 SUCCESS** (25 tests, 0 fallos)

---

## 1. Estado inicial encontrado

| Elemento | Estado |
|---|---|
| `Jenkinsfile` | Existente en la raíz; usa `tools { jdk 'JDK21'; maven 'Maven3' }`, etapas `Verify version`, `Build`, `Test`, `Package`, `Docker Build`, y publica JUnit. |
| `jenkins/Dockerfile` | Basado en `jenkins/jenkins:2.541.3-jdk17`, copia `plugins.txt` y `jenkins.yaml`, define `CASC_JENKINS_CONFIG` y desactiva el setup wizard. |
| `jenkins/docker-compose.yml` | Contenedor `jenkins`, puerto 8080, `env_file: ../.env`, volumen persistente `jenkins_home`, socket `/var/run/docker.sock` montado. |
| `jenkins/jenkins.yaml` | JCasC con usuario admin desde `${JENKINS_ADMIN_PASSWORD}`, credencial `github-token`, y Job DSL con `pipelineJob` + `cpsScm` + `pollSCM`. |
| `jenkins/plugins.txt` | Ya contenía los 8 plugins requeridos más `github-branch-source`, `timestamper` y `junit` (sin duplicados). |
| `.env` / `.env.example` | `.env` ignorado por git; `.env.example` con valores de ejemplo. |
| Contenedor | `jenkins` corriendo con imagen `jenkins-docker-casc:local`. |

No se eliminaron volúmenes, imágenes ni datos de `jenkins_home`. El volumen `jenkins_home` se conservó en cada recreación del contenedor.

---

## 2. Fallos detectados y correcciones aplicadas

### Build #1 — `Unable to find Jenkinsfile from git ...`
El build se disparó a las 13:06 (hora local) y el commit que agregó el `Jenkinsfile` es de las 13:08. Es decir, en ese momento el archivo aún no existía en `master`. No fue un error de configuración; al subir el commit el problema desapareció.

### Build #2 — herramientas no configuradas
```
Tool type "jdk" does not have an install of "JDK21" configured
Tool type "maven" does not have an install of "Maven3" configured
```
El `Jenkinsfile` pide esas herramientas por nombre, pero JCasC no las definía. Se agregó en `jenkins/jenkins.yaml`:

```yaml
tool:
  jdk:
    installations:
      - name: 'JDK21'
        home: '/opt/jdk21'
  maven:
    installations:
      - name: 'Maven3'
        home: '/usr/share/maven'
```

Para no instalar nada dentro de la imagen, esas rutas se proveen montando herramientas ya existentes en el host (ver siguiente sección).

### Build #3 — permiso denegado al socket de Docker
```
permission denied while trying to connect to the docker API at unix:///var/run/docker.sock
```
El socket del host pertenece a `root:docker` con modo `660` y el GID del grupo `docker` en el host es `984`. El usuario `jenkins` (uid 1000) del contenedor no estaba en ese grupo. Se agregó en `jenkins/docker-compose.yml`:

```yaml
group_add:
  - "${DOCKER_GID:-984}"
```

y `DOCKER_GID=984` en `.env` y `.env.example`. Verificar el GID real con `getent group docker | cut -d: -f3`.

### Build #4 — SUCCESS
Con los tres ajustes anteriores, el pipeline completó todas las etapas:
- `Verify version`: JDK 21.0.13.1, Maven 3.9.12, Docker 29.9.0.
- `Build` y `Test`: 25 tests, 0 fallos, 0 errores.
- `Package`: `target/orders.jar` archivado como artefacto.
- `Docker Build`: imágenes `orders-ci:4` y `orders-ci:latest`.

---

## 3. Archivos modificados

| Archivo | Cambio |
|---|---|
| `jenkins/jenkins.yaml` | Sección `tool` con `JDK21` y `Maven3`. Se conservaron admin por env var, credencial, `cpsScm` y `pollSCM H/2 * * * *` con `lightweight()`. |
| `jenkins/docker-compose.yml` | `group_add` con `${DOCKER_GID:-984}` y montajes de solo lectura: `/usr/bin/docker`, JDK 21 del host en `/opt/jdk21`, `/usr/share/maven`, `/usr/share/java` y `/etc/maven`. Se conservó el volumen `jenkins_home` y el socket. |
| `jenkins/plugins.txt` | Se agregó `pipeline-stage-view` (no estaba; el resto ya existía sin duplicados). |
| `.env` | `DOCKER_GID=984`. |
| `.env.example` | `DOCKER_GID=984` y comentarios sobre el modo webhook. |
| `docs/JENKINS_CONFIGURACION.md` | Este documento. |

Montajes añadidos al contenedor (ninguno instala software, solo expone lo que ya está en el host):

```yaml
- /usr/bin/docker:/usr/bin/docker:ro
- /home/jd-velasquez/.jdks/corretto-21.0.13.1:/opt/jdk21:ro
- /usr/share/maven:/usr/share/maven:ro
- /usr/share/java:/usr/share/java:ro
- /etc/maven:/etc/maven:ro
```

> Si la configuración se mueve a otra máquina, esos paths deben existir o cambiarse por los equivalentes locales. Para un entorno portable, conviene construir una imagen de agente con JDK 21 + Maven + Docker CLI.

---

## 4. Ver la ejecución stage a stage (vista gráfica)

El plugin `pipeline-graph-view` (ya presente) agrega la vista gráfica. No está en la pestaña "Console Output" sino en el menú lateral del **build**:

1. Abrir <http://localhost:8080/job/integracion-continua-backend-orders-ci/>.
2. Entrar al build (por ejemplo `#4`).
3. En el menú izquierdo hacer clic en **Pipeline Overview** (URL `/job/.../<n>/stages/`).
4. Ahí se ven los stages (`Verify version`, `Build`, `Test`, `Package`, `Docker Build`) con su avance, duración y logs por paso.

Otros enlaces útiles del mismo menú: **Console Output** (`/console`), **Pipeline Steps** (`/flowGraphTable`) y **Tests** (`/testReport`).

Si no aparece "Pipeline Overview", verificar que el plugin esté activo en `Manage Jenkins > Plugins > Installed` y recargar JCasC.

---

## 5. Verificar que el polling funciona

```bash
git commit --allow-empty -m "trigger jenkins" && git push origin master
docker exec jenkins tail -f /var/jenkins_home/jobs/integracion-continua-backend-orders-ci/scm-polling.log
```

También se puede consultar el estado por API:

```bash
curl -u admin:change-me \
  'http://localhost:8080/job/integracion-continua-backend-orders-ci/lastBuild/api/json?tree=number,result,building'
```

El cron configurado es `H/2 * * * *`, por lo que el cambio debería detectarse en un plazo de ~2 minutos.

---

## 6. Cambiar polling por webhook (Jenkins en local)

El `jenkins.yaml` ya soporta ambos modos mediante la variable `USE_GITHUB_WEBHOOK`:

```groovy
def webhookMode = (System.getenv('USE_GITHUB_WEBHOOK') ?: 'false').toBoolean()
```

- `false` → `pollSCM { scmpoll_spec('H/2 * * * *') }` (modo actual).
- `true` → `githubPush()` (webhook).

Pasos:

1. Exponer Jenkins con un túnel, por ejemplo:
   ```bash
   ngrok http 8080
   # o: smee.io -> webhook relay apuntando a http://localhost:8080/github-webhook/
   ```
2. En el repo de GitHub: `Settings > Webhooks > Add webhook`.
   - **Payload URL:** `https://<tunel>/github-webhook/`
   - **Content type:** `application/json`
   - **Events:** `Just the push event`
3. En `.env`:
   ```env
   USE_GITHUB_WEBHOOK=true
   JENKINS_PUBLIC_URL=https://<tunel>/
   ```
4. Recrear/actualizar el contenedor para que JCasC vuelva a crear el job con el trigger nuevo:
   ```bash
   docker compose -f jenkins/docker-compose.yml up -d
   ```
5. Hacer un push y confirmar que aparece un build con causa `GitHub push`.

---

## 7. Comandos útiles

```bash
# Levantar o recrear Jenkins (conserva jenkins_home)
docker compose -f jenkins/docker-compose.yml up -d --build

# Ver logs de JCasC y del contenedor
docker logs -f jenkins

# Ver logs del job
docker exec jenkins tail -f /var/jenkins_home/jobs/integracion-continua-backend-orders-ci/builds/4/log

# Validar herramientas dentro del contenedor
docker exec jenkins sh -lc 'java -version; /usr/share/maven/bin/mvn -version; docker version'

# Disparar build manual (requiere crumb)
CRUMB=$(curl -s -c /tmp/jcookies -u admin:change-me http://localhost:8080/crumbIssuer/api/json \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["crumb"])')
curl -u admin:change-me -b /tmp/jcookies -H "Jenkins-Crumb: $CRUMB" -X POST \
  http://localhost:8080/job/integracion-continua-backend-orders-ci/build

# Validación local del proyecto
mvn -B clean test
```

---

## 8. Estado final

- Contenedor `jenkins` corriendo, JCasC cargado sin errores (`createOrUpdateConfig for integracion-continua-backend-orders-ci`, `Jenkins is fully up and running`).
- Job creado/actualizado con `pollSCM H/2 * * * *`, `lightweight checkout`, `cpsScm` sobre `master`.
- Herramientas resueltas por JCasC: `JDK21` y `Maven3`; Docker CLI accesible vía socket con el GID correcto.
- **Build #4: SUCCESS** — 25 tests OK, jar archivado, imágenes `orders-ci:4` y `orders-ci:latest` generadas.
- No se hicieron commits: los cambios quedan en el working tree para que los revises y los subas cuando quieras.
