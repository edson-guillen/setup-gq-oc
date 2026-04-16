#!/usr/bin/env bash
# =============================================================
# setup-gq-oc — first-run.sh
# Valida auth OAuth, cria .env, liga proxy e testa endpoint.
# Chamado automaticamente por install.sh na primeira execução.
# =============================================================

# Sem -u: instaladores externos usam variáveis não definidas
set -eo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==>${NC} $1"; }
ok()   { echo -e "  ${GREEN}\xE2\x9C\x93${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC}  $1"; }
err()  { echo -e "  ${RED}X${NC} $1"; }

# Carregar env
ENV_FILE="$HOME/.qwen-openclaude.env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# Garantir PATH do Bun
export PATH="$HOME/.bun/bin:$PATH"

# Garantir PATH do nvm se existir
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_NODE_BIN=$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1 || true)
  [ -n "$NVM_NODE_BIN" ] && export PATH="$NVM_NODE_BIN:$PATH"
fi

echo ""
echo -e "${CYAN}=================================================${NC}"
echo -e "${CYAN}   setup-gq-oc  first-run.sh${NC}"
echo -e "${CYAN}=================================================${NC}"

# -------------------------------------------
# 1. Verificar se já existe conta Qwen
#    Evita `gqwen test`: ele marca contas novas como unavailable em alguns ambientes.
# -------------------------------------------
step "Verificando contas Qwen cadastradas..."
ACCOUNT_LIST=$(gqwen list 2>/dev/null || true)
ACCOUNT_COUNT=$(printf '%s\n' "$ACCOUNT_LIST" | grep -E '^\s*[0-9]+\s+[a-f0-9]+' | wc -l | tr -d '[:space:]')
USABLE_ACCOUNT_COUNT=$(printf '%s\n' "$ACCOUNT_LIST" | grep -E '^\s*[0-9]+\s+[a-f0-9]+.*\s(active|unknown)\s+' | wc -l | tr -d '[:space:]')

if [ "$ACCOUNT_COUNT" -gt 0 ]; then
  ok "$ACCOUNT_COUNT conta(s) Qwen já cadastrada(s)."

  if [ "$USABLE_ACCOUNT_COUNT" -eq 0 ]; then
    warn "Nenhuma conta pronta. Limpando locks/status locais do gqwen-auth..."
    gqwen unlock || true
    ACCOUNT_LIST=$(gqwen list 2>/dev/null || true)
    USABLE_ACCOUNT_COUNT=$(printf '%s\n' "$ACCOUNT_LIST" | grep -E '^\s*[0-9]+\s+[a-f0-9]+.*\s(active|unknown)\s+' | wc -l | tr -d '[:space:]')
  fi

  if [ "$USABLE_ACCOUNT_COUNT" -gt 0 ]; then
    ok "$USABLE_ACCOUNT_COUNT conta(s) pronta(s) para uso."
  else
    warn "Contas cadastradas, mas todas estão indisponíveis."
  fi
fi

if [ "$ACCOUNT_COUNT" -eq 0 ] || [ "$USABLE_ACCOUNT_COUNT" -eq 0 ]; then
  echo ""
  if [ "$ACCOUNT_COUNT" -eq 0 ]; then
    warn "Nenhuma conta Qwen encontrada."
  else
    warn "Necessário renovar autenticação no Qwen."
  fi
  echo ""
  echo -e "  ${CYAN}-------------------------------------------${NC}"
  echo -e "  ${YELLOW}Ação necessária: login no browser${NC}"
  echo -e "  O browser será aberto para autenticação OAuth no qwen.ai."
  echo -e "  Faça login com sua conta gratuita (não precisa de cartão)."
  echo -e "  ${CYAN}-------------------------------------------${NC}"
  echo ""
  gqwen add

  ACCOUNT_LIST=$(gqwen list 2>/dev/null || true)
  ACCOUNT_COUNT=$(printf '%s\n' "$ACCOUNT_LIST" | grep -E '^\s*[0-9]+\s+[a-f0-9]+' | wc -l | tr -d '[:space:]')
  USABLE_ACCOUNT_COUNT=$(printf '%s\n' "$ACCOUNT_LIST" | grep -E '^\s*[0-9]+\s+[a-f0-9]+.*\s(active|unknown)\s+' | wc -l | tr -d '[:space:]')

  if [ "$USABLE_ACCOUNT_COUNT" -eq 0 ]; then
    warn "Login salvo, mas nenhuma conta pronta. Limpando locks/status locais..."
    gqwen unlock || true
    ACCOUNT_LIST=$(gqwen list 2>/dev/null || true)
    USABLE_ACCOUNT_COUNT=$(printf '%s\n' "$ACCOUNT_LIST" | grep -E '^\s*[0-9]+\s+[a-f0-9]+.*\s(active|unknown)\s+' | wc -l | tr -d '[:space:]')
  fi

  if [ "$USABLE_ACCOUNT_COUNT" -eq 0 ]; then
    err "Login concluído, mas nenhuma conta ficou pronta para uso."
    exit 1
  fi

  ok "$USABLE_ACCOUNT_COUNT conta(s) pronta(s) para uso."
fi

# -------------------------------------------
# 2. Iniciar proxy
# -------------------------------------------
step "Iniciando proxy gqwen-auth..."
gqwen serve restart 2>/dev/null || gqwen serve on 2>/dev/null || true
sleep 2

# -------------------------------------------
# 3. Testar endpoint
# -------------------------------------------
step "Testando endpoint do proxy..."
MAX_TRIES=10
TRY=0
while [ $TRY -lt $MAX_TRIES ]; do
  if curl -sf http://localhost:3099/v1/models &>/dev/null; then
    ok "Proxy respondendo em http://localhost:3099/v1"
    break
  fi
  TRY=$((TRY + 1))
  [ $TRY -lt $MAX_TRIES ] && sleep 1
done

if [ $TRY -eq $MAX_TRIES ]; then
  err "Proxy não respondeu após ${MAX_TRIES}s."
  warn "Tente manualmente: gqwen serve on"
  exit 1
fi

# -------------------------------------------
# 4. Validar proxy sem chamar modelo upstream
# -------------------------------------------
step "Validando contas ativas no proxy..."
HEALTH_RESPONSE=$(curl -sf http://localhost:3099/health 2>/dev/null || true)
if echo "$HEALTH_RESPONSE" | grep -Eq '"active":[1-9]'; then
  ok "Proxy tem conta ativa."
else
  warn "Proxy respondeu, mas nao reportou conta ativa. Limpando locks/status locais..."
  gqwen unlock || true
  gqwen serve restart 2>/dev/null || true
  sleep 2
  HEALTH_RESPONSE=$(curl -sf http://localhost:3099/health 2>/dev/null || true)
  if echo "$HEALTH_RESPONSE" | grep -Eq '"active":[1-9]'; then
    ok "Proxy tem conta ativa."
  else
    err "Proxy iniciou, mas nenhuma conta ficou ativa."
    exit 1
  fi
fi

# -------------------------------------------
# Concluído
# -------------------------------------------
echo ""
echo -e "${GREEN}=================================================${NC}"
echo -e "${GREEN}   OK  Tudo pronto!${NC}"
echo -e "${GREEN}=================================================${NC}"
echo ""
echo -e "${CYAN}Abra um novo terminal e use:${NC}"
echo "  qoc-start              -> inicia proxy + OpenClaude aqui"
echo "  qoc-start ~/meu-projeto -> especifica projeto"
echo "  qoc-stop               -> para o proxy"
echo "  qoc-status             -> quota e tokens"
echo "  qoc-doctor             -> diagnostico"
echo ""
