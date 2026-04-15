# setup-gq-oc

> **gqwen-auth** (proxy Qwen gratuito via OAuth) + **OpenClaude** (agente de dev CLI)  
> Um único comando faz todo o setup técnico. Só te pede o login no browser.

---

## Instalação — escolha seu sistema

### 👍 Opção 1: Windows Nativo (recomendado)

**Roda tudo diretamente no Windows, sem WSL.**

```powershell
# PowerShell como Administrador
irm https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/bootstrap/windows-native.ps1 | iex
```

O script:
1. Instala Node.js LTS via winget
2. Instala Bun (runtime JavaScript nativo Windows)
3. Instala gqwen-auth + OpenClaude
4. Configura variáveis de ambiente permanentemente
5. Cria os comandos `qoc-start`, `qoc-stop`, `qoc-status` e `qoc-doctor` no PowerShell
6. Abre o browser **só para o login OAuth no qwen.ai** (inevitável)

---

### 👎 Opção 2: Windows com WSL2

**Instala WSL2 + Ubuntu automaticamente e roda tudo no Linux.**

```powershell
# PowerShell como Administrador
irm https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/bootstrap/windows.ps1 | iex
```

O script:
1. Verifica compatibilidade do Windows (build >= 19041)
2. Instala WSL2 + Ubuntu automaticamente (se necessário)
3. Detecta o nome real da distro registrada (Ubuntu, Ubuntu-24.04, etc.)
4. Inicializa a distro sem interação
5. Executa o setup Linux completo dentro do WSL
6. Cria os comandos `qoc-start`, `qoc-stop`, `qoc-status` e `qoc-doctor` no PowerShell
7. Abre o browser **só para o login OAuth no qwen.ai** (inevitável)

> Se precisar reiniciar para ativar WSL2, o script agenda a retomada automática após o reboot.

---

### Linux / macOS / WSL2

```bash
curl -fsSL https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/scripts/install.sh | bash
```

---

## Uso diário (após setup)

```bash
qoc-start                    # inicia proxy + abre OpenClaude no diretório atual
qoc-start ~/meu-projeto      # especifica o projeto
qoc-stop                     # para o proxy
qoc-status                   # mostra status, quota e tokens
qoc-doctor                   # diagnóstico completo do ambiente
```

---

## Estrutura

```
setup-gq-oc/
├── bootstrap/
│   ├── windows-native.ps1   # Windows nativo (recomendado)
│   └── windows.ps1          # Windows + WSL2 + Ubuntu
├── scripts/
│   ├── install.sh       # Instala tudo (idempotente) — Linux/macOS/WSL
│   ├── first-run.sh     # Valida auth, cria .env, liga proxy, testa endpoint
│   ├── start.sh         # Uso diário: proxy on + OpenClaude
│   ├── doctor.sh        # Diagnóstico automático do ambiente
│   └── uninstall.sh     # Remoção limpa
├── .env.example         # Variáveis de ambiente com defaults seguros
└── README.md
```

---

## Modelos disponíveis

| `OPENAI_MODEL` | Uso ideal |
|---|---|
| `qwen3-coder-plus` | Código complexo (padrão) |
| `qwen3-coder-flash` | Respostas rápidas / tarefas simples |
| `vision-model` | Análise de imagens + código |
| `coder-model` | Modelo geral de código |

Para trocar de modelo:

**Windows (PowerShell)**:
```powershell
$env:OPENAI_MODEL="qwen3-coder-flash"
```

**Linux/macOS**:
```bash
export OPENAI_MODEL=qwen3-coder-flash
```

---

## Referência de comandos gqwen-auth

| Comando | Descrição |
|---|---|
| `gqwen serve on` | Inicia proxy em background |
| `gqwen serve off` | Para o proxy |
| `gqwen serve logs` | Logs em tempo real |
| `gqwen status` | Uso de tokens, quota, locks |
| `gqwen add` | Adiciona outra conta Qwen |
| `gqwen list` | Lista contas cadastradas |
| `gqwen unlock` | Libera contas bloqueadas por rate limit |
| `gqwen config --strategy round-robin` | Rotação entre múltiplas contas |
| `gqwen models` | Lista modelos disponíveis |

---

## Decisões técnicas

- **Windows nativo é a opção recomendada**: Bun e Node.js funcionam perfeitamente no Windows moderno, sem overhead do WSL
- **Sem `set -u`** em todos os scripts bash: instaladores externos (Bun, nvm) usam variáveis internas que quebram com `unset variable`
- **Node.js via NodeSource apt** (Linux) ou **winget** (Windows): nunca via nvm em scripts não-interativos
- **Script bash passado ao WSL via `/tmp/`**: evita problemas de escape de aspas e here-strings no PowerShell
- **Idempotente**: rodar duas vezes não causa erros nem reinstala o que já existe
- **Detecção robusta de distro**: trata UTF-16 e nomes variados (Ubuntu, Ubuntu-24.04, etc.)
- **Variáveis de ambiente permanentes**: configuradas no nível do usuário (Windows) ou no `.bashrc`/`.zshrc` (Linux/macOS)

---

## Comparação: Windows Nativo vs WSL2

| | Windows Nativo | WSL2 |
|---|---|---|
| **Performance** | ⚡ Máxima (I/O nativo) | ✅ Boa (overhead leve) |
| **Compatibilidade** | ✅ Win10 build 10240+ | ✅ Win10 build 19041+ |
| **Espaço em disco** | ⚡ ~500MB | 📦 ~2GB (Ubuntu + deps) |
| **Tempo de setup** | ⚡ 2-3 min | ⏱️ 5-8 min (instala WSL) |
| **Acesso a arquivos** | ⚡ Direto (`C:\\`) | 🔄 Via `/mnt/c` |
| **Ferramentas Linux** | ❌ Não disponíveis | ✅ Acesso total |

👉 **Recomendação**: Use **Windows Nativo** a menos que precise de ferramentas Linux específicas.

---

## Licença

MIT
