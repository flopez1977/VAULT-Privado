#!/bin/bash
# vault-import-labeled.sh — Importa al vault un archivo de accesos en formato
# libre "Etiqueta: valor" (los típicos accesos.txt / accesos.md de clientes).
#
# Igual que vault-import-env.sh: los valores nunca se imprimen; solo nombres
# de item y verificación. Bloques PEM y randomart se saltan (las claves SSH
# van como archivo a ~/.ssh, no como item).
#
# Uso: vault-import-labeled.sh <archivo> <proyecto> [cuenta] [--stub]

set -euo pipefail

KEYCHAIN="${VAULT_KEYCHAIN:-vault-privado.keychain-db}"
KEYCHAIN_PATH="$HOME/Library/Keychains/$KEYCHAIN"
PREFIX="${VAULT_PREFIX:-vault}"

die() { printf 'vault-import-labeled: %s\n' "$*" >&2; exit 1; }

FILE="${1:-}"; PROJECT="${2:-}"
[ -n "$FILE" ] && [ -n "$PROJECT" ] || die "uso: vault-import-labeled.sh <archivo> <proyecto> [cuenta] [--stub]"
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

# Etiqueta -> KEY_SANEADA (mayúsculas ASCII, no-alfanumérico -> _)
# Sin iconv: en macOS devuelve exit!=0 al transliterar ñ/tildes y set -e mata
# el script. Transliteración con sustituciones de bash.
sanitize() {
  local s="$1"
  s="${s//á/a}"; s="${s//é/e}"; s="${s//í/i}"; s="${s//ó/o}"; s="${s//ú/u}"
  s="${s//ü/u}"; s="${s//ñ/n}"
  s="${s//Á/A}"; s="${s//É/E}"; s="${s//Í/I}"; s="${s//Ó/O}"; s="${s//Ú/U}"
  s="${s//Ü/U}"; s="${s//Ñ/N}"
  printf '%s' "$s" | tr '[:lower:]' '[:upper:]' | sed -E 's/[^A-Z0-9]+/_/g; s/^_+//; s/_+$//'
}

pem_warned=0
process() {  # $1 = "import" | "verify"
  local mode="$1" in_pem=0 line label val key
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$in_pem" -eq 1 ]; then
      case "$line" in *-----END*) in_pem=0 ;; esac
      continue
    fi
    case "$line" in
      *-----BEGIN*)
        in_pem=1
        if [ "$mode" = "import" ] && [ "$pem_warned" -eq 0 ]; then
          printf '  ! bloque PEM: NO se migra como item — la clave va como archivo a ~/.ssh\n' >&2
          pem_warned=1
        fi
        case "$line" in *-----END*) in_pem=0 ;; esac
        continue ;;
      '|'*|'+'*|'#'*|'') continue ;;                    # randomart, comentarios, vacías
      *[Pp]assphrase*again*|*passphrase*empty*) continue ;;  # prompts de ssh-keygen pegados
    esac
    if [[ "$line" =~ ^([^:=]{1,60})[:=][[:space:]]*(.+)$ ]]; then
      label="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
      # descartar líneas que son salida de ssh-keygen, no credenciales
      case "$label" in
        "The key fingerprint is"|"The key's randomart image is"|SHA256|"Enter passphrase"*|"Enter same passphrase"*) continue ;;
      esac
      key="$(sanitize "$label")"
      [ -n "$key" ] || continue
      # etiquetas repetidas en el mismo archivo -> sufijo _2, _3...
      local base="$key" n=1 k
      while :; do
        local dup=0
        if [ "$mode" = "import" ]; then
          for k in "${keys[@]:-}"; do [ "$k" = "$key" ] && dup=1 && break; done
        else
          # en verify reproducir la misma numeración que en import
          local count=0
          for k in "${vkeys[@]:-}"; do [ "$k" = "$key" ] && count=1 && break; done
          dup=$count
        fi
        [ "$dup" -eq 0 ] && break
        n=$((n+1)); key="${base}_$n"
      done
      [ "$mode" = "import" ] || vkeys+=("$key")
      # valores que son solo texto de relleno o URLs sin secreto se importan igual
      if [ "$mode" = "import" ]; then
        security add-generic-password -U -s "$PREFIX/$PROJECT/$key" -a "$ACCOUNT" -w "$val" "$KEYCHAIN"
        keys+=("$key"); labels+=("$label")
        printf '  + %s/%s/%s\n' "$PREFIX" "$PROJECT" "$key"
      else
        local h_orig kc_raw h_kc
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
    fi
  done < "$FILE"
}

keys=(); labels=(); vkeys=()
process import
[ "${#keys[@]}" -gt 0 ] || die "no se encontró ninguna línea 'Etiqueta: valor' en $FILE"
fails=0
process verify
[ "$fails" -eq 0 ] || die "$fails verificaciones fallidas — NO se toca el archivo original"

if [ "$STUB" -eq 1 ]; then
  tmp=$(mktemp)
  {
    printf '# STUB — credenciales migradas al vault (llavero vault-privado) el %s\n' "$(date +%Y-%m-%d)"
    printf '# Este archivo ya NO contiene valores. Para usar un secreto:\n'
    printf '#   ~/.vault-privado/bin/vault.sh run <item> -- <comando>\n'
    printf '#\n# --- Items en el vault (cuenta: %s) ---\n' "$ACCOUNT"
    for i in "${!keys[@]}"; do
      printf '# %-35s -> %s/%s/%s\n' "${labels[$i]}" "$PREFIX" "$PROJECT" "${keys[$i]}"
    done
  } > "$tmp"
  mv "$tmp" "$FILE"
  chmod 600 "$FILE"
  printf 'vault-import-labeled: %s reescrito como stub\n' "$FILE"
fi
printf 'vault-import-labeled: completado — %d items para %s\n' "${#keys[@]}" "$PROJECT"
