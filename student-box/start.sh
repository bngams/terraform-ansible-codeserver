#!/bin/sh
# Démarrage du poste : options du .env appliquées à CHAQUE démarrage, puis code-server.
# (Le home est un volume : ce qui est installé dans l'image ne le mettrait pas à jour.)
set -eu

# --- Extension byte_layers (optionnelle) -------------------------------------
# BYTE_LAYERS_EXTENSION (cf. .env) :
#   vide / off → pas d'extension (et retirée si un démarrage précédent l'avait installée)
#   latest     → dernière version publiée sur Open VSX
#   0.2.0      → cette version exactement
# Une installation ratée (Open VSX injoignable…) ne bloque pas le poste.
EXT_ID=byte-layers.byte-layers
case "${BYTE_LAYERS_EXTENSION:-}" in
  "" | off)
    if code-server --list-extensions | grep -qx "$EXT_ID"; then
      code-server --uninstall-extension "$EXT_ID" || true
    fi
    ;;
  latest)
    code-server --install-extension "$EXT_ID" --force \
      || echo "byte_layers : installation de l'extension impossible, le poste garde ce qui était installé" >&2
    ;;
  *)
    code-server --install-extension "$EXT_ID@$BYTE_LAYERS_EXTENSION" --force \
      || echo "byte_layers : installation de $EXT_ID@$BYTE_LAYERS_EXTENSION impossible, le poste garde ce qui était installé" >&2
    ;;
esac
# Dossier d'arrivée des cours (l'extension y clone ~/byte_layers/<cours>). À ouvrir plutôt
# que le home : un workspace qui contient le dossier des extensions les désactive.
if [ -n "${BYTE_LAYERS_EXTENSION:-}" ] && [ "$BYTE_LAYERS_EXTENSION" != off ]; then
  mkdir -p "$HOME/byte_layers"
fi

# PROXY_DOMAIN (ex: lab3-{{port}}.example.com) → proxy code-server PAR SOUS-DOMAINE :
# https://lab3-3000.example.com sert localhost:3000 à la RACINE (SPA, fetch('/api') OK),
# derrière l'auth code-server. Absent → seul le proxy par chemin /proxy/<port>/ existe.
if [ -n "${PROXY_DOMAIN:-}" ]; then
  exec code-server --bind-addr 0.0.0.0:13337 --auth password --proxy-domain "$PROXY_DOMAIN"
fi
exec code-server --bind-addr 0.0.0.0:13337 --auth password
