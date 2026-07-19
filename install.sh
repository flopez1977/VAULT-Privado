#!/bin/bash
# install.sh — Instalador de VAULT-Privado (macOS).
# Pensado para que lo ejecute tu asistente de IA (Claude Code, Codex...) o tú:
#   git clone https://github.com/flopez1977/VAULT-Privado && cd VAULT-Privado && ./install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.vault-privado/bin"
TRANSITORIO="$HOME/Desktop/Transitorio"
KEYCHAIN="vault-privado.keychain-db"

echo "== VAULT-Privado: instalación =="

# 0) Solo macOS por ahora
if [ "$(uname)" != "Darwin" ]; then
  echo "Por ahora VAULT-Privado es solo para macOS (usa el Llavero del sistema)."
  echo "Versión Windows (Credential Manager) y Linux: en el roadmap del README."
  exit 1
fi

# 1) Copiar la CLI
mkdir -p "$INSTALL_DIR"
cp "$REPO_DIR/bin/vault.sh" "$REPO_DIR/bin/vault-import-env.sh" "$REPO_DIR/bin/vault-import-labeled.sh" "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR"/*.sh
echo "✓ CLI instalada en $INSTALL_DIR"

# 2) Alias 'vault' en el shell (idempotente)
SHELL_RC="$HOME/.zshrc"
[ -n "${BASH_VERSION:-}" ] && [ -f "$HOME/.bashrc" ] && SHELL_RC="$HOME/.bashrc"
if ! grep -q "vault-privado/bin/vault.sh" "$SHELL_RC" 2>/dev/null; then
  printf '\n# VAULT-Privado\nalias vault="$HOME/.vault-privado/bin/vault.sh"\n' >> "$SHELL_RC"
  echo "✓ alias 'vault' añadido a $SHELL_RC (abre una terminal nueva para usarlo)"
else
  echo "✓ alias 'vault' ya existía en $SHELL_RC"
fi

# 3) Carpeta Transitorio en el Escritorio, con archivo virgen
mkdir -p "$TRANSITORIO"
if [ ! -f "$TRANSITORIO/CLAVES.txt" ]; then
  cp "$REPO_DIR/plantilla/CLAVES.txt" "$TRANSITORIO/CLAVES.txt"
fi
if [ ! -f "$TRANSITORIO/LEEME.txt" ]; then
  cp "$REPO_DIR/plantilla/LEEME.txt" "$TRANSITORIO/LEEME.txt"
fi
echo "✓ Carpeta Transitorio creada en el Escritorio (con CLAVES.txt y LEEME.txt)"

# 4) Instrucciones para la IA del usuario
mkdir -p "$HOME/.vault-privado"
cp "$REPO_DIR/PARA-TU-IA.md" "$HOME/.vault-privado/PARA-TU-IA.md"
echo "✓ Instrucciones para tu IA copiadas a ~/.vault-privado/PARA-TU-IA.md"

# 5) Llavero: lo crea el usuario con SU contraseña (nunca el instalador ni la IA)
echo ""
if [ -f "$HOME/Library/Keychains/$KEYCHAIN" ]; then
  echo "✓ El llavero $KEYCHAIN ya existe."
else
  cat <<EOF
== ÚLTIMO PASO (lo haces TÚ, no tu IA) ==

Abre la app Terminal y pega estas dos líneas. La primera te pedirá inventar
la contraseña maestra de tu caja fuerte (dos veces). Guárdala bien y NO se la
digas a nadie — tampoco a tu asistente de IA:

  security create-keychain $KEYCHAIN
  security set-keychain-settings -u -t 3600 $KEYCHAIN

La segunda activa el bloqueo automático a la hora.
EOF
fi

cat <<'EOF'

== Y para que tu IA sepa usarlo ==

Si esta instalación la está haciendo tu IA: que añada ella misma el contenido
de ~/.vault-privado/PARA-TU-IA.md a tus instrucciones persistentes (te pedirá
confirmación; recomendado en Claude Code: ~/.claude/CLAUDE.md global).
Si lo instalas a mano, cópialo tú. A partir de ahí, la frase mágica es:

  "Te he dejado las claves del proyecto X en el Transitorio"

y tu IA guardará todo cifrado, dejará un registro en la carpeta del proyecto
y te pedirá permiso para vaciar el archivo.

Tus claves las ves tú siempre en la app "Acceso a Llaveros" → llavero
vault-privado (se abre con tu contraseña maestra).
EOF
echo "== Instalación completada =="
