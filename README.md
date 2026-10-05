# LDAP de prueba para QA en un VPS

Directorio LDAP público para probar la integración LDAP desde las review apps. Es el mismo servidor que levanta `make ldap-up` en local (OpenLDAP + LDAP Account Manager, con el mismo seed), con dos diferencias:

- **Todos los escenarios de certificado están levantados a la vez**, cada uno en su par de puertos, así QA no necesita entrar al servidor para cambiar de escenario.
- **Una página web con todo lo necesario para configurar la plataforma**: datos de conexión, mapeo de atributos, escenarios con su resultado esperado y los certificados para copiar o descargar. Reemplaza lo que en local imprime `make ldap-config`.

## Qué queda publicado

| Qué | Dónde | Para qué |
|---|---|---|
| Página de info | `https://<LDAP_HOST>/` | Datos para configurar la plataforma y certificados |
| LDAP Account Manager | `https://<LAM_HOST>/` | Ver, crear y editar usuarios del directorio |
| LDAP válido | `<LDAP_HOST>` 389 (LDAP y StartTLS) y 636 (LDAPS) | Escenario principal; el único que administra LAM |
| Con intermedia | 1389 / 1636 | El servidor envía la CA intermedia |
| Sin intermedia | 2389 / 2636 | El servidor no la envía: hay que pegar CA + intermedia |
| Autofirmado | 3389 / 3636 | Certificado autofirmado con `CA:TRUE` |
| Autofirmado no CA | 4389 / 4636 | Autofirmado con `CA:FALSE`, como lo generan las herramientas de un servidor |
| Vencido | 5389 / 5636 | Certificado vencido |

La página de info y LAM piden el usuario y la contraseña web (`WEB_USER`). LAM además pide su propio login: usuario `admin`, con `LDAP_ADMIN_PASSWORD`.

El nombre que no coincide con el certificado se prueba con `LDAP_ALT_HOST`, otro nombre que apunta al mismo VPS.

## Requisitos

- VPS con Ubuntu 24.04 (o similar), 1 vCPU y 1 GB de RAM alcanzan.
- Docker Engine con el plugin de Compose.
- Tres nombres DNS que apunten a la IP del VPS: `LDAP_HOST`, `LDAP_ALT_HOST` y `LAM_HOST`. Sin dominio propio sirven [sslip.io](https://sslip.io) y [nip.io](https://nip.io), que resuelven a la IP que llevan en el nombre. Con la IP `203.0.113.10`:
  - `LDAP_HOST=ldap.203-0-113-10.sslip.io`
  - `LDAP_ALT_HOST=203-0-113-10.nip.io`
  - `LAM_HOST=lam.203-0-113-10.sslip.io`
- Puertos de entrada abiertos: 22, 80, 443, 389, 636 y del 1389 al 5636 que usan los escenarios. Las review apps corren en Heroku sin IP fija, así que los puertos LDAP quedan abiertos a internet.

## Despliegue

1. Copiar esta carpeta al VPS:
   ```bash
   scp -r vps/ usuario@IP:/opt/ldap-qa
   ```
2. En el VPS, instalar Docker (si no está):
   ```bash
   curl -fsSL https://get.docker.com | sh
   sudo usermod -aG docker $USER   # cerrar y volver a abrir la sesión
   ```
3. Abrir los puertos (con `ufw`):
   ```bash
   sudo ufw allow 22,80,443,389,636/tcp
   sudo ufw allow 1389,1636,2389,2636,3389,3636,4389,4636,5389,5636/tcp
   sudo ufw enable
   ```
   Si el proveedor tiene su propio firewall (security group), abrir los mismos puertos ahí.
4. Crear el `.env`:
   ```bash
   cd /opt/ldap-qa
   cp .env.example .env
   docker run --rm caddy:2 caddy hash-password --plaintext 'la-clave-web'
   ```
   Completar los nombres DNS, las contraseñas y el hash que devolvió el comando, entre comillas simples.
5. Levantar:
   ```bash
   sh scripts/up.sh
   ```
   La primera vez genera los certificados de los escenarios para `LDAP_HOST`, arma la página de info y levanta los contenedores. Caddy pide los certificados HTTPS a Let's Encrypt en el primer acceso.
6. Abrir `https://<LDAP_HOST>/` y verificar que se vea la página.

## Cómo lo usa QA

1. Abre la página de info con el usuario web.
2. En la review app sigue los pasos de la página: Personas → Importación y sincronización de usuarios → Desde directorio LDAP → Guardar, y completa la configuración con los datos que muestra.
3. Elige un escenario de la tabla: corrige el puerto (el formulario lo completa solo con 389 o 636), pega el certificado indicado y compara el resultado de "Comprobar conexión" con el esperado.
4. Para crear o editar usuarios entra a LAM. Los cambios se ven en el escenario válido (puertos 389 y 636) y se pueden importar desde la plataforma.

## Operación

| Qué | Comando (en la carpeta del VPS) |
|---|---|
| Volver los usuarios al seed | `sh scripts/reset.sh` |
| Cambiar de nombre DNS | editar `LDAP_HOST` en `.env` y `sh scripts/up.sh` (regenera los certificados de servidor) |
| Regenerar los certificados de servidor | `REGENERATE=1 sh scripts/up.sh` |
| Cambiar el seed | editar `seed.ldif` y `sh scripts/reset.sh` |
| Ver logs | `docker compose logs -f ldap` (o el servicio que corresponda) |
| Bajar todo | `docker compose down` |

La CA de prueba se genera una sola vez y se conserva en `data/certs/`. Regenerar los certificados de servidor no obliga a QA a cambiar lo que ya pegó en la plataforma, salvo la CA intermedia, que se genera de nuevo.

Los servidores LDAP no guardan datos en volúmenes: un reinicio del VPS los conserva, pero recrearlos (`up.sh`, `reset.sh`) vuelve al seed.

## Seguridad

- Los usuarios son ficticios. Igual, usar contraseñas propias en el `.env` y no reutilizarlas.
- El usuario `readonly` y su contraseña figuran en la página de info, que está protegida con el usuario web. La contraseña de `admin` no figura en ninguna parte.
- Los puertos LDAP quedan abiertos a internet. Conviene apagar el VPS (o `docker compose down`) cuando no haya pruebas en curso.
- `data/certs/` tiene las claves privadas de la CA de prueba y de los servidores: no copiarlas a otro lado.

## Archivos

| Archivo | Qué es |
|---|---|
| `docker-compose.yml` | Los seis LDAP, LAM y Caddy |
| `Caddyfile` | HTTPS, autenticación básica, página de info y proxy a LAM |
| `.env.example` | Variables a completar |
| `seed.ldif` | Usuarios del directorio (el mismo de `make ldap-up`) |
| `scripts/up.sh` | Genera lo que falta y levanta todo |
| `scripts/generate_certs.sh` | Certificados de los escenarios para `LDAP_HOST` |
| `scripts/build_site.sh` | Arma la página de info en `data/site/` |
| `scripts/reset.sh` | Vuelve el directorio al seed |

## Estado de las pruebas

Se levantó en local con `CADDY_TLS=internal` y nombres `*.localtest.me`, que resuelven a `127.0.0.1`: `up.sh` generó los certificados y la página, los ocho contenedores arrancaron y Caddy emitió los certificados HTTPS. Falta probarlo en un VPS y conectarse desde una review app.
