#!/usr/bin/env bash
# Roda os Passos 3, 4 e 5 da atividade e salva as saídas em evidencias/.
# Uso (Git Bash/WSL/Linux/macOS, com Docker aberto):
#   ./roteiro.sh invoke      # Passo 3: duas invocações com evento, com tempo
#   ./roteiro.sh curl        # Passo 4: três chamadas HTTP (com o start-api já rodando em outro terminal)
#   ./roteiro.sh timeout     # Passo 5: chamada com demorar=true (com o start-api rodando)
set -u
mkdir -p evidencias
URL="http://127.0.0.1:3000/guias"

case "${1:-}" in
  invoke)
    sam build --use-container | tee evidencias/00-sam-build.txt
    for i in 1 2; do
      echo "=== Invocação $i ===" | tee -a evidencias/01-invoke.txt
      { time sam local invoke -e events/pedido.json ; } 2>&1 | tee -a evidencias/01-invoke.txt
    done
    ;;
  curl)
    ARQ="evidencias/02-curl-${2:-sem-warm}.txt"
    : > "$ARQ"
    for i in 1 2 3; do
      echo "=== Chamada $i ===" | tee -a "$ARQ"
      { time curl -s -X POST "$URL" -H "Content-Type: application/json" \
          -d '{"requisicaoId":"R-002","hospital":"H-Caruaru"}' ; echo ; } 2>&1 | tee -a "$ARQ"
    done
    ;;
  timeout)
    ARQ="evidencias/03-timeout-${2:-3s}.txt"
    { time curl -s -i -X POST "$URL" -H "Content-Type: application/json" \
        -d '{"requisicaoId":"R-003","demorar":true}' ; echo ; } 2>&1 | tee "$ARQ"
    ;;
  *)
    echo "uso: $0 invoke | curl [sem-warm|lazy] | timeout [3s|10s]"; exit 1 ;;
esac
