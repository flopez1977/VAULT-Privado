# LOG — VAULT-Privado

**Última actualización:** 2026-07-19
**Estado actual:** v1 publicada (macOS)

---

## Objetivo del proyecto

Caja fuerte local de credenciales para gente que trabaja con asistentes de IA
(Claude Code, Codex...): secretos cifrados en un llavero macOS dedicado,
lectura granular, `vault run` para usar secretos sin que pasen por el contexto
ni los transcripts, y flujo "carpeta Transitorio" para que el usuario no tenga
que aprender ningún sistema. Producto derivado del vault interno de SNS
(montado y rodado el 2026-07-19 sobre casos reales).

## Stack técnico

Bash + `security` (macOS Keychain). Python solo en el instalador de casos
especiales. Sin dependencias externas, sin servidores.

---

## Historial de sesiones

### [2026-07-19] — v1 inicial publicada
**Estado al inicio:** scripts internos SNS funcionando (sns-vault) tras migrar
~100 credenciales reales; decisión de Fernando de compartir la solución.
**Trabajo realizado:**
- Generalización de la CLI (`vault.sh`, importadores env y labeled): llavero
  `vault-privado.keychain-db`, prefijo de items configurable (`VAULT_PREFIX`,
  default `vault/`), sin referencias internas.
- `install.sh`: CLI a `~/.vault-privado/bin`, alias `vault`, carpeta
  `Transitorio` en el Escritorio con `CLAVES.txt` + `LEEME.txt`, instrucciones
  del llavero (lo crea el usuario con SU contraseña).
- `PARA-TU-IA.md`: reglas para el asistente (preferir `run`, lectura granular,
  flujo Transitorio completo con confirmación antes de vaciar, registro
  `CREDENCIALES.md` por proyecto, claves SSH como archivos).
- `README.md` completo: problema/threat model en llano, cómo funciona,
  instalación por IA, flujo Transitorio, comandos, qué protege y qué no,
  roadmap (Windows/Linux/equipos, siempre local).
- Publicado en GitHub como repo público `flopez1977/VAULT-Privado`.
- Post-publicación (misma sesión): sección README "varios ordenadores /
  sincronización" (Vaultwarden en VPS propio explicado, fuera de esta versión
  — filosofía 100% local); imagen de cabecera (`assets/vault-privado.jpg`,
  ilustración del flujo antes→Transitorio→vault→después); instalación guiada
  por la IA (sección "Para la IA que está instalando esto": la IA añade las
  reglas de PARA-TU-IA.md al CLAUDE.md/AGENTS.md del usuario con confirmación;
  el usuario solo crea su contraseña maestra). Texto de difusión para la
  comunidad Imperio Agéntico redactado (Fernando lo publica).
**Estado al terminar:** v1 en GitHub con README completo, imagen e instalación guiada.
**Pendiente para próxima sesión:**
- [ ] Probar instalación limpia en otra máquina/usuario
- [ ] Versión Windows (Credential Manager / `cmdkey`-`CredentialManager` PS)
- [ ] Versión Linux (secret-tool)
