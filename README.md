# setup-gq-oc

> `gqwen-auth` (proxy Qwen gratuito via OAuth) + `OpenClaude` (agente CLI de dev)  
> Um único comando faz o setup técnico. Só pede login no browser.

---

## Instalação

### Opção 1: Windows nativo (recomendado)

Roda tudo diretamente no Windows, sem WSL.

```powershell
# PowerShell como Administrador
irm https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/bootstrap/windows-native.ps1 | iex
```

Ou, na raiz deste repositório:

```powershell
# PowerShell como Administrador
.\setup.ps1
```

O script:
1. Instala Node.js LTS via `winget`
2. Instala Bun
3. Instala `gqwen-auth` + `OpenClaude`
4. Aplica patch de compatibilidade no `gqwen-auth`
5. Configura variáveis de ambiente permanentes
6. Cria `qoc-start`, `qoc-stop`, `qoc-status` e `qoc-doctor`
7. Abre o browser só para login OAuth no `qwen.ai`

---

### Opção 2: Windows com WSL2

Instala WSL2 + Ubuntu automaticamente e roda tudo no Linux.

```powershell
# PowerShell como Administrador
irm https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/bootstrap/windows.ps1 | iex
```

Ou, na raiz deste repositório:

```powershell
# PowerShell como Administrador
.\setup.ps1 -WSL
```

O script:
1. Verifica compatibilidade do Windows (`build >= 19041`)
2. Instala WSL2 + Ubuntu automaticamente, se necessário
3. Detecta o nome real da distro registrada
4. Inicializa a distro sem interação
5. Executa o setup Linux completo dentro do WSL
6. Cria `qoc-start`, `qoc-stop`, `qoc-status` e `qoc-doctor` no PowerShell
7. Abre o browser só para login OAuth no `qwen.ai`

> Se precisar reiniciar para ativar WSL2, o script agenda retomada automática após o reboot.

---

### Linux / macOS / WSL2

```bash
curl -fsSL https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/scripts/install.sh | bash
```

---

## Uso diário

```bash
qoc-start                    # inicia proxy + abre OpenClaude no diretório atual
qoc-start ~/meu-projeto      # especifica o projeto
qoc-stop                     # para o proxy
qoc-status                   # mostra status, quota e tokens
qoc-doctor                   # diagnóstico completo do ambiente
```

---

## Estrutura

```text
setup-gq-oc/
|-- setup.ps1                # Entry point local para Windows (nativo/WSL)
|-- bootstrap/
|   |-- windows-native.ps1   # Windows nativo
|   `-- windows.ps1          # Windows + WSL2
|-- scripts/
|   |-- install.sh           # Instala tudo (Linux/macOS/WSL)
|   |-- patch-gqwen-auth.mjs # Patch pós-instalação do gqwen-auth
|   |-- first-run.sh         # Login, proxy e teste inicial
|   |-- start.sh             # Uso diário
|   |-- doctor.sh            # Diagnóstico
|   `-- uninstall.sh         # Remoção limpa
|-- .env.example
`-- README.md
```

---

## Modelos disponíveis

| `OPENAI_MODEL` | Uso ideal |
|---|---|
| `qwen3-coder-plus` | Código complexo (padrão) |
| `qwen3-coder-flash` | Respostas rápidas / tarefas simples |
| `vision-model` | Análise de imagens + código |
| `coder-model` | Modelo geral de código |

Troca de modelo:

```powershell
$env:OPENAI_MODEL="qwen3-coder-flash"
```

```bash
export OPENAI_MODEL=qwen3-coder-flash
```

---

## Referência de comandos `gqwen-auth`

| Comando | Descrição |
|---|---|
| `gqwen serve on` | Inicia proxy em background |
| `gqwen serve off` | Para o proxy |
| `gqwen serve logs` | Logs em tempo real |
| `gqwen status` | Uso de tokens, quota e locks |
| `gqwen add` | Adiciona outra conta Qwen |
| `gqwen list` | Lista contas cadastradas |
| `gqwen unlock` | Libera contas bloqueadas por rate limit |
| `gqwen config --strategy round-robin` | Rotação entre múltiplas contas |
| `gqwen models` | Lista modelos disponíveis |

---

## Decisões técnicas

- Windows nativo é a opção recomendada: Bun e Node.js funcionam bem no Windows moderno, sem overhead do WSL
- Patch automático no `gqwen-auth`: evita comandos presos no terminal por bug do upstream
- Sem `set -u` nos scripts bash: instaladores externos usam variáveis internas que quebram com `unset variable`
- Node.js via NodeSource `apt` (Linux) ou `winget` (Windows): nunca via `nvm` em script não interativo
- Script bash passado ao WSL via `/tmp/`: evita problemas de escape de aspas e here-strings no PowerShell
- Idempotente: rodar duas vezes não reinstala o que já existe
- Detecção robusta de distro: trata UTF-16 e nomes variados (`Ubuntu`, `Ubuntu-24.04`, etc.)
- Variáveis de ambiente permanentes: configuradas no nível do usuário (Windows) ou no `.bashrc` / `.zshrc` (Linux/macOS)

---

## Comparação: Windows nativo vs WSL2

| | Windows nativo | WSL2 |
|---|---|---|
| Performance | Máxima (I/O nativo) | Boa (overhead leve) |
| Compatibilidade | Windows 10 build 10240+ | Windows 10 build 19041+ |
| Espaço em disco | ~500MB | ~2GB |
| Tempo de setup | 2-3 min | 5-8 min |
| Acesso a arquivos | Direto (`C:\`) | Via `/mnt/c` |
| Ferramentas Linux | Não | Sim |

Recomendação: use Windows nativo, a menos que precise de ferramentas Linux específicas.

---

## Licença

MIT
