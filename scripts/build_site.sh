#!/bin/sh
# Arma la página de info que publica Caddy (data/site/): datos de conexión,
# escenarios de certificado y los certificados para copiar o descargar.
#
# Uso (desde la carpeta vps/, con .env cargado):  sh scripts/build_site.sh
# Lo llama scripts/up.sh.
set -eu

cd "$(dirname "$0")/.."
: "${LDAP_HOST:?}" "${LDAP_ALT_HOST:?}" "${LDAP_READONLY_PASSWORD:?}"

C=data/certs
S=data/site
mkdir -p "$S/certs"
cp "$C/ca.crt" "$S/certs/ca.crt"
cp "$C/intermediate.crt" "$S/certs/intermediate.crt"
cp "$C/other-ca.crt" "$S/certs/otra-ca.crt"
cp "$C/self-signed/ca.crt" "$S/certs/autofirmado.crt"
cp "$C/self-signed-leaf/ca.crt" "$S/certs/autofirmado-no-ca.crt"
cat "$C/ca.crt" "$C/intermediate.crt" > "$S/certs/ca-mas-intermedia.crt"

pem_block() {
    # $1 id, $2 title, $3 file, $4 when to use it
    cat <<HTML
<section class="cert">
  <div class="cert-head">
    <h3>$2</h3>
    <div>
      <button type="button" data-copy="$1">Copiar</button>
      <a class="btn" href="certs/$3" download>Descargar</a>
    </div>
  </div>
  <p>$4</p>
  <pre id="$1">$(cat "$S/certs/$3")</pre>
</section>
HTML
}

{
cat <<HTML
<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>LDAP de prueba para QA</title>
<style>
  :root { --blue:#0052F7; --navy:#030342; --muted:rgba(3,3,66,.7); --gray:#F6F6F6; --line:#E4E6EF; }
  body { margin:0; font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; color:var(--navy); background:#fff; }
  main { max-width:1000px; margin:0 auto; padding:24px 16px 64px; }
  h1 { color:var(--blue); margin:0 0 4px; }
  h2 { margin-top:40px; border-bottom:1px solid var(--line); padding-bottom:6px; }
  p.lead { color:var(--muted); margin-top:0; }
  table { width:100%; border-collapse:collapse; font-size:14px; }
  th, td { border:1px solid var(--line); padding:6px 8px; text-align:left; vertical-align:top; }
  th { background:var(--gray); color:var(--muted); font-weight:600; }
  code { background:var(--gray); padding:1px 4px; border-radius:3px; }
  .table-wrap { overflow-x:auto; }
  .cert { border:1px solid var(--line); border-radius:6px; padding:12px; margin:16px 0; }
  .cert-head { display:flex; justify-content:space-between; align-items:center; gap:8px; flex-wrap:wrap; }
  .cert h3 { margin:0; font-size:16px; }
  pre { background:var(--gray); padding:8px; overflow-x:auto; font-size:12px; max-height:180px; }
  button, .btn { background:#E8EFFF; color:var(--blue); border:0; border-radius:4px; padding:6px 10px; cursor:pointer; text-decoration:none; font-size:13px; }
  ol li { margin-bottom:6px; }
</style>
</head>
<body>
<main>
<h1>LDAP de prueba para QA</h1>
<p class="lead">Directorio de prueba para la integración LDAP de SMARTFENSE. Los datos son ficticios y se reinician al recrear los servidores.</p>

<h2>Cómo configurarlo en la plataforma</h2>
<ol>
  <li>En la review app: <b>Personas → Importación y sincronización de usuarios</b>, elegir <b>Desde directorio LDAP</b> y <b>Guardar</b>.</li>
  <li>En <b>Configuración LDAP</b>, completar con los datos de abajo. El puerto se completa solo al cambiar el tipo de conexión: <b>corregirlo</b> según el escenario.</li>
  <li>Con LDAPS o StartTLS y <b>Validar</b>, pegar en <b>Certificado de la autoridad certificante</b> el certificado que indica el escenario.</li>
  <li><b>Comprobar conexión</b> y comparar con el resultado esperado.</li>
</ol>

<h2>Datos de conexión</h2>
<div class="table-wrap"><table>
  <tr><th>Campo</th><th>Valor</th></tr>
  <tr><td>Host</td><td><code>${LDAP_HOST}</code></td></tr>
  <tr><td>Bind DN</td><td><code>cn=readonly,dc=smartfense,dc=local</code></td></tr>
  <tr><td>Bind Password</td><td><code>${LDAP_READONLY_PASSWORD}</code></td></tr>
  <tr><td>Base DN</td><td><code>ou=personas,dc=smartfense,dc=local</code></td></tr>
  <tr><td>Filtro LDAP</td><td><code>(objectClass=inetOrgPerson)</code></td></tr>
</table></div>

<h3>Mapeo de atributos</h3>
<div class="table-wrap"><table>
  <tr><th>Campo</th><th>Atributo</th></tr>
  <tr><td>Email</td><td><code>mail</code></td></tr>
  <tr><td>Nombre / Apellido / Nombre completo</td><td><code>givenName</code> / <code>sn</code> / <code>displayName</code></td></tr>
  <tr><td>Grupos</td><td><code>ou</code></td></tr>
  <tr><td>Áreas funcionales</td><td><code>departmentNumber</code></td></tr>
  <tr><td>Niveles jerárquicos</td><td><code>title</code></td></tr>
  <tr><td>Idioma</td><td><code>preferredLanguage</code></td></tr>
  <tr><td>Teléfono</td><td><code>telephoneNumber</code></td></tr>
  <tr><td>ID Empleado</td><td><code>employeeNumber</code></td></tr>
  <tr><td>Manager</td><td><code>manager</code></td></tr>
  <tr><td>Atributo de estado / Valor que indica inactivo</td><td><code>description</code> / <code>DISABLED</code></td></tr>
</table></div>

<h2>Escenarios de certificado</h2>
<p>Cada escenario es un servidor con los mismos usuarios, en su propio par de puertos. Resultados con <b>Validar</b>.</p>
<div class="table-wrap"><table>
  <tr><th>Escenario</th><th>LDAP / StartTLS</th><th>LDAPS</th><th>Certificado a pegar</th><th>Resultado esperado</th></tr>
  <tr><td>Válido</td><td>389</td><td>636</td><td>CA de prueba</td><td>Conecta. Sin certificado o con la otra CA: "no es de confianza".</td></tr>
  <tr><td>Nombre que no coincide</td><td>389</td><td>636</td><td>CA de prueba, con Host <code>${LDAP_ALT_HOST}</code></td><td>"El certificado del servidor no corresponde al host configurado."</td></tr>
  <tr><td>Con CA intermedia</td><td>1389</td><td>1636</td><td>CA de prueba</td><td>Conecta: el servidor envía la intermedia.</td></tr>
  <tr><td>Sin enviar la intermedia</td><td>2389</td><td>2636</td><td>CA de prueba / CA + intermedia</td><td>Solo la CA: "no es de confianza". CA + intermedia: conecta.</td></tr>
  <tr><td>Autofirmado</td><td>3389</td><td>3636</td><td>Autofirmado</td><td>Conecta.</td></tr>
  <tr><td>Autofirmado sin CA:TRUE</td><td>4389</td><td>4636</td><td>Autofirmado no CA</td><td>Conecta.</td></tr>
  <tr><td>Vencido</td><td>5389</td><td>5636</td><td>CA de prueba</td><td>"No es de confianza o está vencido". Con No validar, conecta.</td></tr>
</table></div>
<p>LDAP sin cifrar: puerto 389, tipo LDAP, sin certificado.</p>

<h2>Certificados</h2>
HTML
pem_block ca "CA de prueba" ca.crt "Escenarios válido, con intermedia, sin intermedia y vencido."
pem_block intermediate "CA intermedia" intermediate.crt "Para pegar debajo de la CA de prueba en el escenario sin intermedia."
pem_block bundle "CA de prueba + intermedia" ca-mas-intermedia.crt "Las dos juntas, listas para pegar."
pem_block selfsigned "Autofirmado" autofirmado.crt "Escenario autofirmado."
pem_block leaf "Autofirmado no CA" autofirmado-no-ca.crt "Escenario autofirmado sin CA:TRUE."
pem_block other "Otra CA" otra-ca.crt "CA que no firmó ningún servidor: siempre da \"no es de confianza\"."
cat <<HTML

<h2>Usuarios del directorio</h2>
<p>En <code>ou=personas</code>, que es el Base DN, hay 12 entradas: 9 personas activas con área, nivel y manager (<code>bmartinez</code> tiene un manager que no existe), una inactiva (<code>dsilva</code>, <code>description: DISABLED</code>), una con mail inválido (<code>mbad</code>) y una sin mail (<code>serviceaccount</code>). Fuera del Base DN: la directora (<code>ou=direccion</code>, manager de los gerentes) y un proveedor (<code>ou=externos</code>).</p>
<p>Para crear o editar usuarios: <a href="/">LDAP Account Manager</a>, usuario <code>admin</code> (contraseña: la de administrador del directorio, la tiene quien administra el VPS). Lo que se edite ahí impacta solo en el servidor del escenario válido (puertos 389 y 636).</p>
</main>
<script>
document.querySelectorAll("button[data-copy]").forEach(function (button) {
  button.addEventListener("click", function () {
    var text = document.getElementById(button.dataset.copy).textContent;
    navigator.clipboard.writeText(text).then(function () {
      button.textContent = "Copiado";
      setTimeout(function () { button.textContent = "Copiar"; }, 1500);
    });
  });
});
</script>
</body>
</html>
HTML
} > "$S/index.html"

echo "Página de info generada en $S/index.html"
