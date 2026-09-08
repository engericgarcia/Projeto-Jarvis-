#!/bin/bash
# Sobe o Jarvis na versão navegador (não precisa compilar nada).
set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTA="${PORT:-4321}"

if lsof -nP -iTCP:"$PORTA" -sTCP:LISTEN >/dev/null 2>&1; then
    echo "Já tem algo escutando na porta $PORTA. Abrindo o navegador."
    open "http://127.0.0.1:$PORTA"
    exit 0
fi

# Abre o navegador assim que o servidor subir.
( sleep 1; open "http://127.0.0.1:$PORTA" ) &

echo "Ctrl+C para parar."
PORT="$PORTA" exec node "$RAIZ/navegador/servidor.mjs"
