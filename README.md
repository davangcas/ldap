# LDAP de prueba para QA

Directorio LDAP público para probar la integración LDAP de SMARTFENSE desde las review apps. Es el mismo servidor que levanta `make ldap-up` en el repo de SMARTFENSE (OpenLDAP + LDAP Account Manager, con el mismo seed), con dos diferencias:

- **Todos los escenarios de certificado están levantados a la vez**, cada uno en su par de puertos, así QA no necesita entrar al servidor para cambiar de escenario.
- **Una página web con todo lo necesario para configurar la plataforma**: datos de conexión, mapeo de atributos, escenarios con su resultado esperado y los certificados para copiar o descargar.

## Qué queda publicado

| Qué | Dónde | Para qué |
|---|---|---|
| Página de info | `https://<LDAP_HOST>/` (nginx → `127.0.0.1:8041`) | Datos para configurar la plataforma y certificados |
| LDAP Account Manager | `https://<LAM_HOST>/` (nginx → `127.0.0.1:8040`) | Ver, crear y editar usuarios del directorio |
| LDAP válido | `<LDAP_HOST>` 389 (LDAP y StartTLS) y 636 (LDAPS) | Escenario principal; el único que administra LAM |
| Con intermedia | 1389 / 1636 | El servidor envía la CA intermedia |
| Sin intermedia | 2389 / 2636 | El servidor no la envía: hay que pegar CA + intermedia |
| Autofirmado | 3389 / 3636 | Certificado autofirmado con `CA:TRUE` |
| Autofirmado no CA | 4389 / 4636 | Autofirmado con `CA:FALSE`, como lo generan las herramientas de un servidor |
| Vencido | 5389 / 5636 | Certificado vencido |

La página de info y LAM piden el usuario y la contraseña web (`WEB_USER`). LAM además pide su propio login: usuario `admin`, con `LDAP_ADMIN_PASSWORD`.

El nombre que no coincide con el certificado se prueba con `LDAP_ALT_HOST`, otro nombre que apunta al mismo servidor.

Los LDAP se publican directo desde Docker, sin pasar por nginx: es tráfico LDAP, no HTTP.

## Requisitos

- Servidor con Docker y el plugin de Compose.
- nginx en el servidor, con certbot para el HTTPS de la página de info y de LAM.
- Tres nombres DNS que apunten a la IP del servidor: `LDAP_HOST`, `LDAP_ALT_HOST` y `LAM_HOST`.
- Puertos de entrada abiertos: 389, 636 y del 1389 al 5636. Las review apps corren en Heroku sin IP fija, así que quedan abiertos a internet.
- Libres en el servidor: esos puertos LDAP, y `127.0.0.1:8040` y `127.0.0.1:8041` (se cambian con `LAM_PORT` e `INFO_PORT` en el `.env`).
- Memoria: el bundle suma ocho contenedores. Comprobar con `free -m` que haya al menos 500 MB disponibles.

## Despliegue

1. **Bajar el despliegue anterior antes de actualizar el repo.** El compose anterior levantaba `smartfense-ldap` y `smartfense-ldap-admin`, y este último ocupa `127.0.0.1:8040`:
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
   Completar los nombres DNS, las contraseñas y el hash que devolvió el comando, entre comillas simples. La contraseña de `readonly` se muestra en la página de info: tiene que ser distinta de la de `admin`.
3. Abrir los puertos LDAP en el firewall del servidor y en el del proveedor:
   ```bash
   sudo ufw allow 389,636,1389,1636,2389,2636,3389,3636,4389,4636,5389,5636/tcp
   ```
4. Levantar:
   ```bash
   sh scripts/up.sh
   ```
   La primera vez genera los certificados de los escenarios para `LDAP_HOST`, arma la página de info y levanta los contenedores.
5. Publicar la página y LAM en nginx: tomar `nginx-example.conf` como base, ajustar los nombres, obtener los certificados con certbot y recargar nginx:
   ```bash
   sudo certbot --nginx -d <LDAP_HOST> -d <LAM_HOST>
   sudo nginx -t && sudo systemctl reload nginx
   ```
   Si nginx ya tenía un sitio apuntando al LAM viejo en `127.0.0.1:8040`, sigue funcionando: el LAM nuevo queda en el mismo puerto, ahora con la autenticación web delante.
6. Abrir `https://<LDAP_HOST>/` y verificar que se vea la página.

## Cómo lo usa QA

1. Abre la página de info con el usuario web.
2. En la review app sigue los pasos de la página: Personas → Importación y sincronización de usuarios → Desde directorio LDAP → Guardar, y completa la configuración con los datos que muestra.
3. Elige un escenario de la tabla: corrige el puerto (el formulario lo completa solo con 389 o 636), pega el certificado indicado y compara el resultado de "Comprobar conexión" con el esperado.
4. Para crear o editar usuarios entra a LAM. Los cambios se ven en el escenario válido (puertos 389 y 636) y se pueden importar desde la plataforma.

## Operación

| Qué | Comando |
|---|---|
| Volver los usuarios al seed | `sh scripts/reset.sh` |
| Cambiar de nombre DNS | editar `LDAP_HOST` en `.env` y `sh scripts/up.sh` (regenera los certificados de servidor) |
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
| `docker-compose.yml` | Los seis LDAP, LAM y la página de info |
| `Caddyfile` | Autenticación básica, página de info y proxy a LAM, en puertos locales |
| `nginx-example.conf` | Ejemplo para publicarlos por HTTPS con el nginx del servidor |
| `.env.example` | Variables a completar |
| `seed.ldif` | Usuarios del directorio (el mismo de `make ldap-up`) |
| `scripts/up.sh` | Genera lo que falta y levanta todo |
| `scripts/generate_certs.sh` | Certificados de los escenarios para `LDAP_HOST` |
| `scripts/build_site.sh` | Arma la página de info en `data/site/` |
| `scripts/reset.sh` | Vuelve el directorio al seed |
