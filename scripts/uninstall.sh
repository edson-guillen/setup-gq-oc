#!/usr/bin/env bash
# =============================================================
# setup-gq-oc — uninstall.sh
# Remove gqwen-auth, OpenClaude e configurações de forma limpa.
# =============================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; NC='\033[0m'
step() { echo -e "\n${CYAN}==>${NC} $1"; }
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC}  $1"; }

export PATH="$HOME/.bun/bin:$PATH"

echo ""
echo -e "${YELLOW}╔══════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║   🗑️  setup-gq-oc  uninstall.sh             ║${NC}"
echo -e "${YELLOW}╚══════════════════════════════════════════════╝${NC}"
echo ""

step "Parando proxy gqwen-auth..."
gqwen serve off 2>/dev/null || true
ok "Proxy parado."

step "Removendo gqwen-auth..."
bun uninstall -g gqwen-auth 2>/dev/null || true
ok "gqwen-auth removido."

step "Removendo OpenClaude..."
npm uninstall -g openclaude 2>/dev/null || sudo npm uninstall -g openclaude 2>/dev/null || true
ok "OpenClaude removido."

echo ""
read -r -p "$(echo -e "${YELLOW}Remover dados do gqwen (~/.gqwen), .env e repo local? [s/N]${NC} ")" confirm
if [[ "$confirm" =~ ^[sS]$ ]]; then
  rm -rf ~/.gqwen
  rm -f ~/.qwen-openclaude.env
  rm -rf ~/setup-gq-oc
  ok "Dados, .env e repositório removidos."
else
  warn "Dados mantidos. Remova manualmente se quiser:"
  echo "    rm -rf ~/.gqwen ~/.qwen-openclaude.env ~/setup-gq-oc"
fi

# Remover aliases e linhas do shell RC
SHELL_RC="$HOME/.zshrc"
[ -f "$HOME/.bashrc" ] && SHELL_RC="$HOME/.bashrc"
[ -f "$HOME/.zshrc" ]  && SHELL_RC="$HOME/.zshrc"

if grep -q 'setup-gq-oc\|qwen-openclaude\|qoc-start\|qoc-stop\|qoc-status\|qoc-doctor' "$SHELL_RC" 2>/dev/null; then
  # Remover blocos setup-gq-oc do shell RC
  sed -i '/# setup-gq-oc/,/# ─\{40\}/d' "$SHELL_RC" 2>/dev/null || true
  sed -i '/qwen-openclaude\.env/d' "$SHELL_RC" 2>/dev/null || true
  sed -i '/qoc-start\|qoc-stop\|qoc-status\|qoc-doctor/d' "$SHELL_RC" 2>/dev/null || true
  ok "Aliases qoc-* removidos de $SHELL_RC"
else
  warn "Nenhum alias qoc-* encontrado em $SHELL_RC"
fi

echo ""
echo -e "${GREEN}✓${NC} Desinstalação concluída."
echo ""
