#!/usr/bin/env bash
# =============================================================
# setup-gq-oc — install.sh
# Instala dependências de forma idempotente em Linux/macOS/WSL.
# Uso direto: curl -fsSL https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/scripts/install.sh | bash
# =============================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==>${NC} $1"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }
err()  { echo -e "  ${RED}✗${NC} $1"; }

echo -e ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   🤖  setup-gq-oc  install.sh               ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"

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
# 2. Instalar dependências base (git, curl, unzip)
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
    err "Gerenciador de pacotes não reconhecido. Instale manualmente: ${MISSING[*]}"
    exit 1
  fi
fi
ok "curl, git, unzip disponíveis."

# -------------------------------------------
# 3. Instalar Node.js (LTS) se não existir
# -------------------------------------------
step "Verificando Node.js..."
if ! command -v node &>/dev/null; then
  warn "Node.js não encontrado. Instalando via nvm..."
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  # shellcheck disable=SC1090
  [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
  nvm install --lts
  nvm use --lts

  # Persistir nvm no shell RC
  if ! grep -q 'NVM_DIR' "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'NVMEOF'

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"
NVMEOF
  fi
fi
ok "Node.js $(node --version)"

# -------------------------------------------
# 4. Instalar Bun
# -------------------------------------------
step "Verificando Bun..."
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

if command -v bun &>/dev/null; then
  ok "Bun já instalado: $(bun --version)"
else
  warn "Instalando Bun..."
  curl -fsSL https://bun.sh/install | bash
  # shellcheck disable=SC1090
  source "$HOME/.bun/env" 2>/dev/null || true
  export PATH="$HOME/.bun/bin:$PATH"
  ok "Bun instalado: $(bun --version)"
fi

# Persistir Bun no shell RC
if ! grep -q 'BUN_INSTALL' "$SHELL_RC" 2>/dev/null; then
  cat >> "$SHELL_RC" << 'BUNEOF'

# Bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
BUNEOF
fi

# -------------------------------------------
# 5. Instalar gqwen-auth
# -------------------------------------------
step "Instalando gqwen-auth..."
bun install -g gqwen-auth
ok "gqwen-auth $(gqwen --version 2>/dev/null || echo 'instalado')"

# -------------------------------------------
# 6. Instalar OpenClaude
# -------------------------------------------
step "Instalando OpenClaude..."
npm install -g openclaude 2>/dev/null || {
  warn "Tentando com sudo..."
  sudo npm install -g openclaude
}
ok "OpenClaude instalado."

# -------------------------------------------
# 7. Clonar/atualizar o repositório
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
# 8. Configurar variáveis de ambiente
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
# shellcheck disable=SC1090
source "$ENV_FILE"

# -------------------------------------------
# 9. Criar comandos qoc-* no shell
# -------------------------------------------
step "Criando aliases qoc-*..."

if ! grep -q 'qoc-start' "$SHELL_RC" 2>/dev/null; then
  cat >> "$SHELL_RC" << 'ALIASEOF'

# ─── setup-gq-oc commands ───────────────────────────────────
alias qoc-stop="gqwen serve off"
alias qoc-status="gqwen status"
alias qoc-doctor="bash ~/setup-gq-oc/scripts/doctor.sh"

qoc-start() {
  local project="${1:-$(pwd)}"
  gqwen serve on 2>/dev/null || true
  cd "$project" && openclaude
}
# ────────────────────────────────────────────────────────────
ALIASEOF
  ok "Aliases qoc-* adicionados."
else
  ok "Aliases qoc-* já presentes."
fi

# -------------------------------------------
# Concluído — chamar first-run.sh
# -------------------------------------------
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   ✅  Dependências instaladas!               ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""

# Se não foi chamado pelo windows.ps1, executar first-run diretamente
if [ "${SKIP_FIRST_RUN:-}" != "1" ]; then
  bash "$REPO_DIR/scripts/first-run.sh"
fi
