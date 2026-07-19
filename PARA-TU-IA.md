# VAULT-Privado — Instrucciones para el asistente de IA

> Este bloque va en las instrucciones persistentes del asistente (CLAUDE.md,
> AGENTS.md o equivalente). **No hace falta que lo copies tú a mano**: la IA
> que instala VAULT-Privado se encarga de añadirlo, pidiéndote confirmación y
> recomendándote el mejor sitio (ver README, sección "Para la IA que está
> instalando esto").

## Caja fuerte de credenciales (VAULT-Privado) — OBLIGATORIO

Todas las credenciales de proyectos (SSH, FTP, passwords, API keys) viven
cifradas en el llavero macOS dedicado `vault-privado` — nunca en claro en
`.md`, `.txt`, `.env` de referencia, logs, commits ni chat.

CLI: `~/.vault-privado/bin/vault.sh` (alias `vault`).
Convención de items: `vault/<proyecto>/<CAMPO>` (campo en mayúsculas).

### Reglas en toda sesión

1. **Preferir `vault.sh run <item> -- <comando>`** — inyecta el secreto como
   variable de entorno al proceso hijo; el valor nunca entra al contexto ni a
   los transcripts. `vault.sh get` solo si no hay alternativa técnica.
2. **Lectura granular**: solo el item que necesita la tarea. Nunca listar
   valores ni volcar el vault entero.
3. El llavero `login` del usuario (banca, certificados personales) **no se
   toca jamás**.
4. Credencial nueva que aparezca en una sesión → guardarla con
   `printf '%s' 'valor' | vault.sh set vault/<proyecto>/<CAMPO> <cuenta>`
   (valor por stdin) + actualizar el registro del proyecto.

### Flujo "Transitorio" (cuando el usuario diga que dejó claves ahí)

Frase típica: *"Te he dejado las claves del proyecto X en el Transitorio"*.
La carpeta es `~/Desktop/Transitorio/` y el archivo `CLAVES.txt`.

Pasos que DEBES seguir, en orden:

1. **Importar sin mirar**: usa los importadores (no leas el archivo entero al
   contexto si puedes evitarlo):
   - Formato `VARIABLE=valor` → `vault-import-env.sh <archivo> <proyecto>`
   - Formato `Etiqueta: valor` → `vault-import-labeled.sh <archivo> <proyecto>`
   Ambos verifican cada item por hash y solo imprimen nombres, nunca valores.
2. **Claves SSH privadas** (bloques `-----BEGIN ... KEY-----`): los
   importadores las saltan a propósito. Extráelas a un archivo en `~/.ssh/`
   con `chmod 600` (usa `awk '/BEGIN/,/END/'`, sin imprimir el contenido) y
   guarda su passphrase (si la hay) como item del vault.
3. **Registro en el proyecto**: crea o actualiza en la carpeta del proyecto un
   archivo `CREDENCIALES.md` que diga: las credenciales de este proyecto están
   en el llavero `vault-privado`, items `vault/<proyecto>/*` (lista de nombres,
   SIN valores), clave SSH en `~/.ssh/<archivo>` si aplica, y cómo usarlas
   (`vault.sh run/get`). Así cualquier sesión futura sabe dónde mirar, y el
   usuario sabe que lo ve visualmente en la app "Acceso a Llaveros".
4. **Confirmar y vaciar**: muestra al usuario la lista de items guardados
   (solo nombres) y PIDE CONFIRMACIÓN para vaciar `CLAVES.txt` (restaurar la
   plantilla). No lo vacíes sin su OK explícito. Nunca borres la carpeta
   Transitorio.

### Qué no hacer nunca

- No pedir al usuario su contraseña maestra del llavero, ni guardarla en
  ningún sitio.
- No escribir valores de credenciales en archivos, chat, logs ni commits.
- No listar el contenido (valores) del llavero.
- No usar el Transitorio como almacén permanente.
