#!/bin/bash
# vault-import-env.sh — Importa un archivo .env al vault vault-privado y verifica.
#
# Diseñado para que un agente pueda migrar credenciales SIN ver los valores:
# los secretos van del archivo al llavero dentro de este proceso; a la salida
# solo se imprimen nombres de variables y OK/FAIL de verificación (por hash).
#
# Uso:
#   vault-import-env.sh <archivo.env> <proyecto> [cuenta] [--stub]
#
#   <proyecto>  se usa en el nombre del item: vault/<proyecto>/<VARIABLE>
#   [cuenta]    cuenta del item en el llavero (default: <proyecto>)
#   --stub      tras verificar TODO en OK, reescribe el archivo como
#               stub-puntero: conserva las líneas de comentario y sustituye
#               cada VARIABLE=valor por la referencia al item del vault.

set -euo pipefail

KEYCHAIN="${VAULT_KEYCHAIN:-vault-privado.keychain-db}"
KEYCHAIN_PATH="$HOME/Library/Keychains/$KEYCHAIN"
PREFIX="${VAULT_PREFIX:-vault}"

die() { printf 'vault-import: %s\n' "$*" >&2; exit 1; }

FILE="${1:-}"; PROJECT="${2:-}"
[ -n "$FILE" ] && [ -n "$PROJECT" ] || die "uso: vault-import-env.sh <archivo.env> <proyecto> [cuenta] [--stub]"
shift 2
ACCOUNT="$PROJECT"; STUB=0
while [ $# -gt 0 ]; do
  case "$1" in
    --stub) STUB=1; shift ;;
    *)      ACCOUNT="$1"; shift ;;
  esac
done

[ -f "$FILE" ] || die "no existe: $FILE"
[ -f "$KEYCHAIN_PATH" ] || die "el llavero $KEYCHAIN no existe (vault.sh init)"

strip_quotes() {
  local v="$1"
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  printf '%s' "$v"
}

# --- Pasada 1: importar ---
# Los bloques PEM (claves privadas/certificados multilínea) NO se migran como
# items: una clave SSH debe vivir como archivo en ~/.ssh con permisos 600.
keys=()
in_pem=0
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$in_pem" -eq 1 ]; then
    case "$line" in *-----END*) in_pem=0 ;; esac
    continue
  fi
  case "$line" in
    *-----BEGIN*)
      in_pem=1
      printf '  ! bloque PEM detectado (clave/certificado multilínea): NO se migra como item.\n' >&2
      printf '    Extraerlo a un archivo en ~/.ssh (chmod 600) y referenciarlo en el índice.\n' >&2
      case "$line" in *-----END*) in_pem=0 ;; esac
      continue ;;
    '#'*|'') continue ;;
  esac
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="$(strip_quotes "${BASH_REMATCH[2]}")"
    [ -n "$val" ] || { printf '  - %s: valor vacío, se omite\n' "$key"; continue; }
    security add-generic-password -U -s "$PREFIX/$PROJECT/$key" -a "$ACCOUNT" -w "$val" "$KEYCHAIN"
    keys+=("$key")
    printf '  + %s/%s/%s\n' "$PREFIX" "$PROJECT" "$key"
  fi
done < "$FILE"

[ "${#keys[@]}" -gt 0 ] || die "no se encontró ninguna VARIABLE=valor en $FILE"

# --- Pasada 2: verificar por hash (nunca se imprimen valores) ---
# Nota: `security ... -w` imprime en HEX los valores con bytes no ASCII
# (tildes, ñ...). Se comparan ambas formas.
fails=0
in_pem=0
while IFS= read -r line || [ -n "$line" ]; do
  if [ "$in_pem" -eq 1 ]; then
    case "$line" in *-----END*) in_pem=0 ;; esac
    continue
  fi
  case "$line" in
    *-----BEGIN*) in_pem=1; case "$line" in *-----END*) in_pem=0 ;; esac; continue ;;
    '#'*|'') continue ;;
  esac
  if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
    key="${BASH_REMATCH[1]}"
    val="$(strip_quotes "${BASH_REMATCH[2]}")"
    [ -n "$val" ] || continue
    h_orig=$(printf '%s' "$val" | shasum -a 256 | cut -d' ' -f1)
    kc_raw=$(security find-generic-password -s "$PREFIX/$PROJECT/$key" -a "$ACCOUNT" -w "$KEYCHAIN" \
             | { IFS= read -r v || true; printf '%s' "$v"; })
    h_kc=$(printf '%s' "$kc_raw" | shasum -a 256 | cut -d' ' -f1)
    if [ "$h_orig" != "$h_kc" ] && printf '%s' "$kc_raw" | grep -qE '^([0-9a-fA-F]{2})+$'; then
      h_kc=$(printf '%s' "$kc_raw" | xxd -r -p | shasum -a 256 | cut -d' ' -f1)
    fi
    if [ "$h_orig" = "$h_kc" ]; then
      printf '  ✓ verificado %s/%s/%s\n' "$PREFIX" "$PROJECT" "$key"
    else
      printf '  ✗ FALLO verificación %s/%s/%s\n' "$PREFIX" "$PROJECT" "$key"
      fails=$((fails+1))
    fi
  fi
done < "$FILE"

[ "$fails" -eq 0 ] || die "$fails verificaciones fallidas — NO se toca el archivo original"

# --- Pasada 3 (opcional): reescribir como stub-puntero ---
if [ "$STUB" -eq 1 ]; then
  tmp=$(mktemp)
  {
    printf '# STUB — credenciales migradas al vault (llavero vault-privado) el %s\n' "$(date +%Y-%m-%d)"
    printf '# Este archivo ya NO contiene valores. Para usar un secreto:\n'
    printf '#   ~/.vault-privado/bin/vault.sh run <item> -- <comando>\n'
    printf '#   ~/.vault-privado/bin/vault.sh get <item>   (excepcional)\n'
    printf '#\n'
    printf '# --- Comentarios del archivo original (contexto, sin secretos) ---\n'
    grep '^#' "$FILE" || true
    printf '#\n# --- Items en el vault (cuenta: %s) ---\n' "$ACCOUNT"
    for key in "${keys[@]}"; do
      printf '# %-30s -> %s/%s/%s\n' "$key" "$PREFIX" "$PROJECT" "$key"
    done
  } > "$tmp"
  mv "$tmp" "$FILE"
  chmod 600 "$FILE"
  printf 'vault-import: %s reescrito como stub (%d items)\n' "$FILE" "${#keys[@]}"
fi

printf 'vault-import: completado — %d items en el vault para el proyecto %s\n' "${#keys[@]}" "$PROJECT"
