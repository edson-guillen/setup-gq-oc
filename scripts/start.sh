#!/usr/bin/env bash
# =============================================================
# setup-gq-oc — start.sh  (uso diário)
# Garante proxy ligado e abre OpenClaude no projeto informado.
# Uso: bash start.sh [caminho-do-projeto]
# Alias: qoc-start [caminho]
# =============================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "${CYAN}==>${NC} $1"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }

# Carregar env
ENV_FILE="$HOME/.qwen-openclaude.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"
export PATH="$HOME/.bun/bin:$PATH"

# Verificar dependências
if ! command -v gqwen &>/dev/null; then
  err "gqwen-auth não encontrado. Execute o install.sh primeiro:"
  echo "  curl -fsSL https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/scripts/install.sh | bash"
  exit 1
fi

if ! command -v openclaude &>/dev/null; then
  err "openclaude não encontrado. Execute o install.sh primeiro."
  exit 1
fi

# Garantir que há pelo menos uma conta cadastrada
ACCOUNT_COUNT=$(gqwen list 2>/dev/null | grep -c '@' || echo 0)
if [ "$ACCOUNT_COUNT" -eq 0 ]; then
  warn "Nenhuma conta Qwen encontrada. Iniciando login..."
  gqwen add
fi

# Iniciar proxy se necessário
step "Verificando proxy..."
if curl -sf http://localhost:3099/v1/models &>/dev/null; then
  ok "Proxy já rodando."
else
  step "Iniciando proxy gqwen-auth..."
  gqwen serve on
  sleep 2
  if curl -sf http://localhost:3099/v1/models &>/dev/null; then
    ok "Proxy iniciado em http://localhost:3099/v1"
  else
    err "Proxy não respondeu. Verifique com: gqwen serve logs"
    exit 1
  fi
fi

# Navegar para o projeto
PROJECT="${1:-$(pwd)}"
if [ -d "$PROJECT" ]; then
  cd "$PROJECT"
  ok "Projeto: $PROJECT"
else
  warn "Diretório '$PROJECT' não encontrado. Usando diretório atual."
fi

step "Modelo: ${OPENAI_MODEL:-qwen3-coder-plus}"
echo ""

# Abrir OpenClaude
openclaude
