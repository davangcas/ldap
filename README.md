# LDAP de prueba para QA

Directorio LDAP público para probar la integración LDAP de SMARTFENSE desde las review apps. Es el mismo servidor que levanta `make ldap-up` en el repo de SMARTFENSE (OpenLDAP + LDAP Account Manager, con el mismo seed), con dos diferencias:

- **Todos los escenarios de certificado están levantados a la vez**, cada uno en su par de puertos, así QA no necesita entrar al servidor para cambiar de escenario.
- **Una página web con todo lo necesario para configurar la plataforma**: datos de conexión, mapeo de atributos, escenarios con su resultado esperado y los certificados para copiar o descargar.

## Qué queda publicado

| Qué | Dónde | Para qué |
|---|---|---|
| LDAP Account Manager | `https://<LDAP_HOST>/` | Ver, crear y editar usuarios del directorio |
| Página de info | `https://<LDAP_HOST>/info/` | Datos para configurar la plataforma y certificados |
| LDAP válido | `<LDAP_HOST>` 389 (LDAP y StartTLS) y 636 (LDAPS) | Escenario principal; el único que administra LAM |
| Con intermedia | 1389 / 1636 | El servidor envía la CA intermedia |
| Sin intermedia | 2389 / 2636 | El servidor no la envía: hay que pegar CA + intermedia |
| Autofirmado | 3389 / 3636 | Certificado autofirmado con `CA:TRUE` |
| Autofirmado no CA | 4389 / 4636 | Autofirmado con `CA:FALSE`, como lo generan las herramientas de un servidor |
| Vencido | 5389 / 5636 | Certificado vencido |

LAM y la página de info piden el usuario y la contraseña web (`WEB_USER`). LAM además pide su propio login: usuario `admin`, con `LDAP_ADMIN_PASSWORD`.

El nombre que no coincide con el certificado se prueba con `LDAP_ALT_HOST`, que puede ser la IP pública del servidor.

## Cómo encaja en el servidor

El servidor ya tiene nginx con dos cosas que el bundle reutiliza tal cual, sin cambios:

| nginx | Hacia | Qué atiende ahora |
|---|---|---|
| `stream` en el 389 | `localhost:8030` | El LDAP válido (LDAP y StartTLS) |
| Sitio HTTPS `ldap-admin.davangcas.site` (certbot) | `localhost:8040` | Caddy: LAM en `/` y la página de info en `/info/`, con autenticación |

El resto de los puertos LDAP (636 y del 1389 al 5636) los publica Docker directamente: nginx no los usa.

## Requisitos

- Docker con el plugin de Compose (ya está).
- Los puertos 636 y del 1389 al 5636 abiertos a internet, en el firewall del servidor y en el del proveedor. Las review apps corren en Heroku sin IP fija.
- Memoria: el bundle suma ocho contenedores. Comprobar con `free -m` que haya al menos 500 MB disponibles.

## Despliegue

1. **Bajar el despliegue anterior antes de actualizar el repo.** El compose anterior levantaba `smartfense-ldap` y `smartfense-ldap-admin`, que ocupan `127.0.0.1:8030` y `127.0.0.1:8040`:
   ```bash
   cd ~/ldap
   docker compose down
   ```
   Si el repo ya se actualizó antes de bajarlo, borrar los dos contenedores a mano:
   ```bash
   docker rm -f smartfense-ldap smartfense-ldap-admin
   ```
2. Actualizar el repo y crear el `.env`:
   ```bash
   git pull
   cp .env.example .env
   docker run --rm caddy:2 caddy hash-password --plaintext 'la-clave-web'
   ```
   Completar la IP pública en `LDAP_ALT_HOST`, las contraseñas y el hash que devolvió el comando, entre comillas simples. La contraseña de `readonly` se muestra en la página de info: tiene que ser distinta de la de `admin`.
3. Abrir los puertos LDAP nuevos:
   ```bash
   sudo ufw allow 636,1389,1636,2389,2636,3389,3636,4389,4636,5389,5636/tcp
   ```
   Si el proveedor tiene su propio firewall, abrir los mismos puertos ahí.
4. Levantar:
   ```bash
   sh scripts/up.sh
   ```
   La primera vez genera los certificados de los escenarios para `LDAP_HOST`, arma la página de info y levanta los contenedores.
5. Abrir `https://<LDAP_HOST>/info/` y verificar que se vea la página.

## Cómo lo usa QA

1. Abre la página de info con el usuario web.
2. En la review app sigue los pasos de la página: Personas → Importación y sincronización de usuarios → Desde directorio LDAP → Guardar, y completa la configuración con los datos que muestra.
3. Elige un escenario de la tabla: corrige el puerto (el formulario lo completa solo con 389 o 636), pega el certificado indicado y compara el resultado de "Comprobar conexión" con el esperado.
4. Para crear o editar usuarios entra a LAM. Los cambios se ven en el escenario válido (puertos 389 y 636) y se pueden importar desde la plataforma.

## Operación

| Qué | Comando |
|---|---|
| Volver los usuarios al seed | `sh scripts/reset.sh` |
| Regenerar los certificados de servidor | `REGENERATE=1 sh scripts/up.sh` |
| Cambiar el seed | editar `seed.ldif` y `sh scripts/reset.sh` |
| Ver logs | `docker compose logs -f ldap` (o el servicio que corresponda) |
| Bajar todo | `docker compose down` |

La CA de prueba se genera una sola vez y se conserva en `data/certs/`. Regenerar los certificados de servidor no obliga a QA a cambiar lo que ya pegó en la plataforma, salvo la CA intermedia, que se genera de nuevo.

Los servidores LDAP no guardan datos en volúmenes: un reinicio del servidor los conserva, pero recrearlos (`up.sh`, `reset.sh`) vuelve al seed.

## Seguridad

- Los usuarios son ficticios. Igual, usar contraseñas propias en el `.env` y no reutilizarlas.
- El usuario `readonly` y su contraseña figuran en la página de info, que está protegida con el usuario web. La contraseña de `admin` no figura en ninguna parte.
- Los puertos LDAP quedan abiertos a internet, en un servidor que corre otros servicios. Conviene bajar los contenedores (`docker compose down`) cuando no haya pruebas en curso.
- `data/certs/` tiene las claves privadas de la CA de prueba y de los servidores: no copiarlas a otro lado.

## Archivos

| Archivo | Qué es |
|---|---|
| `docker-compose.yml` | Los seis LDAP, LAM y Caddy |
| `Caddyfile` | Autenticación básica, LAM en `/` y página de info en `/info/` |
| `.env.example` | Variables a completar |
| `seed.ldif` | Usuarios del directorio (el mismo de `make ldap-up`) |
| `scripts/up.sh` | Genera lo que falta y levanta todo |
| `scripts/generate_certs.sh` | Certificados de los escenarios para `LDAP_HOST` |
| `scripts/build_site.sh` | Arma la página de info en `data/site/` |
| `scripts/reset.sh` | Vuelve el directorio al seed |
