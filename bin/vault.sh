#!/bin/bash
# vault.sh — VAULT-Privado: caja fuerte local sobre un llavero macOS dedicado.
#
# El llavero vault-privado.keychain-db es un archivo SEPARADO de tu llavero
# login: tus credenciales personales (banca, certificados) viven en login y
# esta herramienta NUNCA lo toca. Cifrado en reposo por macOS.
#
# Reglas de uso (ver README del repo):
#   1. Preferir `run` sobre `get`: el secreto se inyecta al proceso hijo como
#      variable de entorno y nunca pasa por la salida (ni por el contexto de
#      un agente, ni por los transcripts de sesión).
#   2. Nunca volcar el vault entero: `list` solo muestra nombres.
#   3. Ningún secreto en claro en .md, logs, commits ni chat.
#
# Convención de nombres: servicio = vault/<proyecto>/<campo>
#   ej. vault/miproyecto/SSH_PASSWORD  (cuenta = usuario del acceso o el proyecto)

set -euo pipefail

KEYCHAIN="${VAULT_KEYCHAIN:-vault-privado.keychain-db}"
KEYCHAIN_PATH="$HOME/Library/Keychains/$KEYCHAIN"

die() { printf 'vault: %s\n' "$*" >&2; exit 1; }

usage() {
  cat >&2 <<'EOF'
Uso:
  vault.sh init                                  Instrucciones para crear el llavero
  vault.sh set <servicio> [cuenta]               Guarda/actualiza (valor por stdin)
  vault.sh get <servicio> [cuenta]               Imprime UN secreto (uso excepcional)
  vault.sh run <servicio> [-a cuenta] [--as VAR] -- <cmd...>
                                                 Ejecuta cmd con el secreto en $VAULT_SECRET
                                                 (o en VAR) sin imprimirlo nunca
  vault.sh list                                  Lista nombres de items (nunca valores)
  vault.sh delete <servicio> [cuenta] [--yes]    Borra un item

Ejemplos:
  printf '%s' 'mi-password' | vault.sh set vault/miproyecto/SSH_PASSWORD claude
  vault.sh run vault/miproyecto/SSH_PASSWORD --as SSHPASS -- sshpass -e ssh user@host
EOF
  exit 1
}

require_keychain() {
  [ -f "$KEYCHAIN_PATH" ] || die "el llavero $KEYCHAIN no existe. Ejecuta: vault.sh init"
}

cmd_init() {
  if [ -f "$KEYCHAIN_PATH" ]; then
    echo "El llavero $KEYCHAIN ya existe en $KEYCHAIN_PATH"
    exit 0
  fi
  cat <<EOF
El llavero no existe todavía. Créalo TÚ en tu Terminal (te pedirá elegir una
contraseña — solo tuya, no la compartas con nadie ni con ningún agente):

  security create-keychain $KEYCHAIN
  security set-keychain-settings -u -t 3600 $KEYCHAIN   # autobloqueo 1h

Después avisa para continuar con la migración.
EOF
}

cmd_set() {
  local svc="${1:-}" acct="${2:-vault}"
  [ -n "$svc" ] || usage
  require_keychain
  if [ -t 0 ]; then
    printf 'Pega el valor y pulsa Enter (no se mostrará):\n' >&2
    IFS= read -rs secret
    printf '\n' >&2
  else
    IFS= read -r secret || true
  fi
  [ -n "${secret:-}" ] || die "valor vacío, no se guarda nada"
  security add-generic-password -U -s "$svc" -a "$acct" -w "$secret" "$KEYCHAIN"
  printf 'vault: guardado %s (cuenta: %s)\n' "$svc" "$acct" >&2
}

cmd_get() {
  local svc="${1:-}" acct="${2:-}"
  [ -n "$svc" ] || usage
  require_keychain
  if [ -n "$acct" ]; then
    security find-generic-password -s "$svc" -a "$acct" -w "$KEYCHAIN"
  else
    security find-generic-password -s "$svc" -w "$KEYCHAIN"
  fi
}

cmd_list() {
  require_keychain
  security dump-keychain "$KEYCHAIN" 2>/dev/null | awk -F'"' '
    /"acct"<blob>=/ { acct=$4 }
    /"svce"<blob>=/ { printf "%s\t(cuenta: %s)\n", $4, acct; acct="" }
  ' | sort
}

cmd_run() {
  local svc="${1:-}"; [ -n "$svc" ] || usage; shift
  local acct="" var="VAULT_SECRET"
  while [ $# -gt 0 ]; do
    case "$1" in
      -a)   acct="${2:-}"; shift 2 ;;
      --as) var="${2:-}"; shift 2 ;;
      --)   shift; break ;;
      *)    die "argumento inesperado: $1 (¿falta '--' antes del comando?)" ;;
    esac
  done
  [ $# -gt 0 ] || die "falta el comando a ejecutar tras '--'"
  printf '%s' "$var" | grep -qE '^[A-Za-z_][A-Za-z0-9_]*$' || die "nombre de variable inválido: $var"
  require_keychain
  local secret
  if [ -n "$acct" ]; then
    secret=$(security find-generic-password -s "$svc" -a "$acct" -w "$KEYCHAIN")
  else
    secret=$(security find-generic-password -s "$svc" -w "$KEYCHAIN")
  fi
  exec env "$var=$secret" "$@"
}

cmd_delete() {
  local svc="${1:-}"; [ -n "$svc" ] || usage; shift
  local acct="" yes=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --yes) yes=1; shift ;;
      *)     acct="$1"; shift ;;
    esac
  done
  require_keychain
  if [ "$yes" -ne 1 ]; then
    [ -t 0 ] || die "sin TTY hace falta --yes para borrar"
    printf '¿Borrar %s del vault? (escribe "si"): ' "$svc" >&2
    IFS= read -r resp
    [ "$resp" = "si" ] || die "cancelado"
  fi
  if [ -n "$acct" ]; then
    security delete-generic-password -s "$svc" -a "$acct" "$KEYCHAIN" >/dev/null
  else
    security delete-generic-password -s "$svc" "$KEYCHAIN" >/dev/null
  fi
  printf 'vault: borrado %s\n' "$svc" >&2
}

cmd="${1:-}"; [ -n "$cmd" ] && shift || usage
case "$cmd" in
  init)   cmd_init "$@" ;;
  set)    cmd_set "$@" ;;
  get)    cmd_get "$@" ;;
  run)    cmd_run "$@" ;;
  list)   cmd_list "$@" ;;
  delete) cmd_delete "$@" ;;
  *)      usage ;;
esac
