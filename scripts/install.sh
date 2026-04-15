#!/usr/bin/env bash
# =============================================================
# setup-gq-oc — install.sh
# Instala dependências de forma idempotente em Linux/macOS/WSL.
# Uso direto: curl -fsSL https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/scripts/install.sh | bash
# =============================================================

# Sem -u: scripts externos (bun installer, etc.) usam variáveis não definidas
set -eo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==>${NC} $1"; }
ok()   { echo -e "  ${GREEN}\xE2\x9C\x93${NC} $1"; }
warn() { echo -e "  ${YELLOW}!${NC}  $1"; }
err()  { echo -e "  ${RED}X${NC} $1"; }

echo -e ""
echo -e "${CYAN}==================================================${NC}"
echo -e "${CYAN}   setup-gq-oc  install.sh${NC}"
echo -e "${CYAN}==================================================${NC}"

# -------------------------------------------
# 1. Detectar shell e SO
# -------------------------------------------
step "Detectando ambiente..."
SHELL_RC="$HOME/.bashrc"
if [ -n "${ZSH_VERSION:-}" ] || [ "${SHELL:-}" = "/bin/zsh" ] || [ "${SHELL:-}" = "/usr/bin/zsh" ]; then
  SHELL_RC="$HOME/.zshrc"
fi
ok "Shell RC: $SHELL_RC"

IS_WSL=false
if grep -qi microsoft /proc/version 2>/dev/null; then IS_WSL=true; fi
$IS_WSL && ok "Ambiente WSL detectado." || ok "Ambiente nativo."

# -------------------------------------------
# 2. Dependências base
# -------------------------------------------
step "Verificando dependências base..."
MISSING=()
for cmd in curl git unzip; do
  command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
if [ ${#MISSING[@]} -gt 0 ]; then
  warn "Instalando: ${MISSING[*]}"
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq "${MISSING[@]}"
  elif command -v brew &>/dev/null; then
    brew install "${MISSING[@]}"
  else
    err "Instale manualmente: ${MISSING[*]}"; exit 1
  fi
fi
ok "curl, git, unzip disponíveis."

# -------------------------------------------
# 3. Node.js — via NodeSource apt (nunca nvm em scripts não-interativos)
# -------------------------------------------
step "Verificando Node.js..."

# Garantir que node do nvm também seja detectado, se existir
if [ -d "$HOME/.nvm/versions/node" ]; then
  NVM_NODE_BIN=$(ls -d "$HOME"/.nvm/versions/node/*/bin 2>/dev/null | sort -V | tail -1 || true)
  if [ -n "$NVM_NODE_BIN" ]; then
    export PATH="$NVM_NODE_BIN:$PATH"
  fi
fi

if command -v node &>/dev/null; then
  ok "Node.js já disponível: $(node --version)"
else
  if command -v apt-get &>/dev/null; then
    warn "Instalando Node.js 22 LTS via NodeSource (apt)..."
    # Remover nvm para evitar conflito (mantém o diretório, só remove do PATH ativo)
    unset NVM_DIR 2>/dev/null || true
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y -qq nodejs
    ok "Node.js instalado: $(node --version)"
  elif command -v brew &>/dev/null; then
    warn "Instalando Node.js via brew..."
    brew install node
    ok "Node.js instalado: $(node --version)"
  else
    err "Não foi possível instalar Node.js. Acesse: https://nodejs.org"
    exit 1
  fi
fi
ok "npm $(npm --version)"

# -------------------------------------------
# 4. Bun
# -------------------------------------------
step "Verificando Bun..."
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

if command -v bun &>/dev/null; then
  ok "Bun já instalado: $(bun --version)"
else
  warn "Instalando Bun..."
  curl -fsSL https://bun.sh/install | bash
  [ -f "$HOME/.bun/env" ] && . "$HOME/.bun/env" || true
  export PATH="$HOME/.bun/bin:$PATH"
  ok "Bun instalado: $(bun --version)"
fi

if ! grep -q 'BUN_INSTALL' "$SHELL_RC" 2>/dev/null; then
  cat >> "$SHELL_RC" << 'BUNEOF'

# Bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
BUNEOF
fi

# -------------------------------------------
# 5. gqwen-auth
# -------------------------------------------
step "Instalando gqwen-auth..."
bun install -g gqwen-auth
ok "gqwen-auth instalado."

# -------------------------------------------
# 6. OpenClaude
# -------------------------------------------
step "Instalando OpenClaude..."
if ! npm install -g openclaude 2>/dev/null; then
  warn "Tentando com sudo..."
  sudo npm install -g openclaude
fi
ok "OpenClaude instalado."

# -------------------------------------------
# 7. Repositório local
# -------------------------------------------
step "Verificando repositório setup-gq-oc..."
REPO_DIR="$HOME/setup-gq-oc"
if [ -d "$REPO_DIR/.git" ]; then
  git -C "$REPO_DIR" pull --ff-only 2>/dev/null || warn "Não foi possível atualizar o repositório."
  ok "Repositório atualizado em $REPO_DIR"
else
  git clone https://github.com/edson-guillen/setup-gq-oc.git "$REPO_DIR"
  ok "Repositório clonado em $REPO_DIR"
fi
chmod +x "$REPO_DIR"/scripts/*.sh

# -------------------------------------------
# 8. Variáveis de ambiente
# -------------------------------------------
step "Configurando variáveis de ambiente..."
ENV_FILE="$HOME/.qwen-openclaude.env"
cat > "$ENV_FILE" << 'ENVEOF'
# setup-gq-oc — gerado automaticamente
export CLAUDE_CODE_USE_OPENAI=1
export OPENAI_BASE_URL=http://localhost:3099/v1
export OPENAI_API_KEY=gqwen-proxy
export OPENAI_MODEL=qwen3-coder-plus
ENVEOF

SOURCE_LINE="source \"$ENV_FILE\""
if ! grep -qF "$ENV_FILE" "$SHELL_RC" 2>/dev/null; then
  { echo ""; echo "# setup-gq-oc"; echo "$SOURCE_LINE"; } >> "$SHELL_RC"
  ok "Variáveis adicionadas a $SHELL_RC"
else
  ok "Variáveis já presentes em $SHELL_RC"
fi
. "$ENV_FILE"

# -------------------------------------------
# 9. Aliases qoc-*
# -------------------------------------------
step "Criando aliases qoc-*..."
if ! grep -q 'qoc-start' "$SHELL_RC" 2>/dev/null; then
  cat >> "$SHELL_RC" << 'ALIASEOF'

# --- setup-gq-oc commands ---
alias qoc-stop="gqwen serve off"
alias qoc-status="gqwen status"
alias qoc-doctor="bash ~/setup-gq-oc/scripts/doctor.sh"

qoc-start() {
  local project="${1:-$(pwd)}"
  gqwen serve on 2>/dev/null || true
  cd "$project" && openclaude
}
# --- fim setup-gq-oc ---
ALIASEOF
  ok "Aliases qoc-* adicionados."
else
  ok "Aliases qoc-* já presentes."
fi

# -------------------------------------------
# Concluído
# -------------------------------------------
echo ""
echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN}   OK  Depend\u00eancias instaladas!${NC}"
echo -e "${GREEN}==================================================${NC}"
echo ""

if [ "${SKIP_FIRST_RUN:-}" != "1" ]; then
  bash "$REPO_DIR/scripts/first-run.sh"
fi
