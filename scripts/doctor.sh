#!/usr/bin/env bash
# =============================================================
# setup-gq-oc — doctor.sh
# Diagnóstico automático do ambiente. Verifica todas as peças.
# Uso: qoc-doctor  |  bash ~/setup-gq-oc/scripts/doctor.sh
# =============================================================

# Sem -u e sem -e: doctor deve continuar mesmo que algo falhe
set -o pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
check() { echo -e "  ${GREEN}\xE2\x9C\x93${NC} $1"; }
fail()  { echo -e "  ${RED}X${NC} $1"; FAILURES=$((FAILURES+1)); }
warn()  { echo -e "  ${YELLOW}!${NC}  $1"; WARNINGS=$((WARNINGS+1)); }
info()  { echo -e "  ${CYAN}.${NC} $1"; }

FAILURES=0; WARNINGS=0

echo ""
echo -e "${BOLD}${CYAN}=================================================${NC}"
echo -e "${BOLD}${CYAN}   setup-gq-oc  doctor.sh${NC}"
echo -e "${BOLD}${CYAN}=================================================${NC}"
echo ""

# Carregar env
ENV_FILE="$HOME/.qwen-openclaude.env"
export PATH="$HOME/.bun/bin:$PATH"
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_NODE_BIN=$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1 || true)
  [ -n "$NVM_NODE_BIN" ] && export PATH="$NVM_NODE_BIN:$PATH"
fi
[ -f "$ENV_FILE" ] && source "$ENV_FILE" || true

# -------------------------------------------
echo -e "${BOLD}[ Sistema ]${NC}"
uname_out=$(uname -sr 2>/dev/null || echo 'desconhecido')
info "SO: $uname_out"
if grep -qi microsoft /proc/version 2>/dev/null; then
  info "Ambiente: WSL"
else
  info "Ambiente: Nativo"
fi

# -------------------------------------------
echo ""
echo -e "${BOLD}[ Ferramentas ]${NC}"

if command -v bun &>/dev/null; then
  check "Bun: $(bun --version)"
else
  fail "Bun não encontrado. Instale: curl -fsSL https://bun.sh/install | bash"
fi

if command -v node &>/dev/null; then
  check "Node.js: $(node --version)"
else
  fail "Node.js não encontrado."
fi

if command -v npm &>/dev/null; then
  check "npm: $(npm --version)"
else
  fail "npm não encontrado."
fi

if command -v git &>/dev/null; then
  check "git: $(git --version | awk '{print $3}')"
else
  fail "git não encontrado."
fi

if command -v curl &>/dev/null; then
  check "curl disponível."
else
  fail "curl não encontrado."
fi

if command -v rg &>/dev/null; then
  check "ripgrep: $(rg --version | head -1)"
else
  fail "ripgrep não encontrado. Instale: sudo apt-get install -y ripgrep"
fi

# -------------------------------------------
echo ""
echo -e "${BOLD}[ gqwen-auth ]${NC}"

if command -v gqwen &>/dev/null; then
  check "gqwen-auth instalado."
else
  fail "gqwen-auth não encontrado. Execute: bun install -g gqwen-auth"
fi

ACCOUNT_COUNT=$(gqwen list 2>/dev/null | grep -c '@' || echo 0)
if [ "$ACCOUNT_COUNT" -gt 0 ]; then
  check "$ACCOUNT_COUNT conta(s) Qwen cadastrada(s)."
else
  fail "Nenhuma conta Qwen. Execute: gqwen add"
fi

# -------------------------------------------
echo ""
echo -e "${BOLD}[ Proxy ]${NC}"

if curl -sf http://localhost:3099/v1/models &>/dev/null; then
  check "Proxy rodando em http://localhost:3099/v1"
else
  fail "Proxy não responde. Execute: gqwen serve on"
fi

# -------------------------------------------
echo ""
echo -e "${BOLD}[ OpenClaude ]${NC}"

if command -v openclaude &>/dev/null; then
  check "openclaude instalado."
else
  fail "openclaude não encontrado. Execute: npm install -g @gitlawb/openclaude"
fi

# -------------------------------------------
echo ""
echo -e "${BOLD}[ Variáveis de Ambiente ]${NC}"

if [ -f "$ENV_FILE" ]; then
  check "Arquivo .env presente: $ENV_FILE"
else
  fail "Arquivo .env ausente: $ENV_FILE"
fi

if [ -n "${CLAUDE_CODE_USE_OPENAI:-}" ]; then
  check "CLAUDE_CODE_USE_OPENAI=1"
else
  fail "CLAUDE_CODE_USE_OPENAI não definido"
fi

if [ -n "${OPENAI_BASE_URL:-}" ]; then
  check "OPENAI_BASE_URL=${OPENAI_BASE_URL}"
else
  fail "OPENAI_BASE_URL não definido"
fi

if [ -n "${OPENAI_MODEL:-}" ]; then
  check "OPENAI_MODEL=${OPENAI_MODEL}"
else
  warn "OPENAI_MODEL não definido (padrão: qwen3-coder-plus)"
fi

# -------------------------------------------
echo ""
echo -e "${BOLD}[ Teste de API ]${NC}"

if curl -sf http://localhost:3099/v1/models &>/dev/null; then
  TEST=$(curl -sf http://localhost:3099/v1/chat/completions \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${OPENAI_MODEL:-qwen3-coder-plus}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say: OK\"}],\"max_tokens\":5}" 2>/dev/null || echo '')
  if echo "$TEST" | grep -qi 'choices'; then
    check "Chamada de teste bem-sucedida!"
  else
    warn "Proxy ativo mas modelo não respondeu. Verifique: gqwen status"
  fi
else
  warn "Proxy offline — teste de API ignorado."
fi

# -------------------------------------------
echo ""
if [ $FAILURES -gt 0 ]; then
  echo -e "${RED}=================================================${NC}"
  echo -e "${RED}  $FAILURES erro(s) encontrado(s). Veja acima.${NC}"
  echo -e "${RED}=================================================${NC}"
else
  echo -e "${GREEN}=================================================${NC}"
  echo -e "${GREEN}  OK  Tudo OK! $WARNINGS aviso(s).${NC}"
  echo -e "${GREEN}=================================================${NC}"
fi
echo ""
