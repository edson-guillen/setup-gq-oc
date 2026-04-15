#Requires -Version 5.1
<#
.SYNOPSIS
    setup-gq-oc — Bootstrap Windows Nativo
    Instala gqwen-auth + OpenClaude diretamente no Windows (sem WSL).

.USAGE
    # PowerShell como Administrador:
    irm https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/bootstrap/windows-native.ps1 | iex
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -------------------------------------------------------
# Helpers visuais
# -------------------------------------------------------
function Write-Step  { param($msg) Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok    { param($msg) Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn  { param($msg) Write-Host "  [!]  $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "  [X]  $msg" -ForegroundColor Red }
function Write-Banner {
    Write-Host ""
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |   setup-gq-oc  Windows Nativo            |" -ForegroundColor Cyan
    Write-Host "  |   gqwen-auth + OpenClaude (sem WSL)      |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host ""
}

Write-Banner

# -------------------------------------------------------
# 1. Verificar privilégios de Administrador
# -------------------------------------------------------
Write-Step "Verificando privilégios..."
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Execute o PowerShell como Administrador."
    Write-Host "  Clique com botão direito no PowerShell > 'Executar como administrador'"
    Write-Host "  Depois rode o comando novamente." -ForegroundColor Yellow
    exit 1
}
Write-Ok "Rodando como Administrador."

# -------------------------------------------------------
# 2. Verificar versão do Windows
# -------------------------------------------------------
Write-Step "Verificando compatibilidade do Windows..."
$build = [System.Environment]::OSVersion.Version.Build
$winVer = (Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion').DisplayVersion 2>$null
if ($null -eq $winVer) { $winVer = "Windows $([System.Environment]::OSVersion.Version)" }

if ($build -lt 10240) {
    Write-Err "Windows build $build detectado. Requer Windows 10 build 10240+ ou Windows 11."
    exit 1
}
Write-Ok "$winVer (build $build) — compatível."

# -------------------------------------------------------
# 3. Instalar Node.js via winget
# -------------------------------------------------------
Write-Step "Verificando Node.js..."
$nodeInstalled = $false
try {
    $nodeVersion = node --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $nodeInstalled = $true
        Write-Ok "Node.js já instalado: $nodeVersion"
    }
} catch { $nodeInstalled = $false }

if (-not $nodeInstalled) {
    Write-Warn "Instalando Node.js via winget..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements -e
        # Atualizar PATH para incluir Node.js recém-instalado
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        Start-Sleep -Seconds 2
        $nodeVersion = node --version 2>$null
        Write-Ok "Node.js instalado: $nodeVersion"
    } else {
        Write-Err "winget não encontrado. Instale Node.js manualmente: https://nodejs.org"
        exit 1
    }
}

$npmVersion = npm --version 2>$null
Write-Ok "npm $npmVersion"

# -------------------------------------------------------
# 4. Instalar Bun
# -------------------------------------------------------
Write-Step "Verificando Bun..."
$bunInstalled = $false
try {
    $bunVersion = bun --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $bunInstalled = $true
        Write-Ok "Bun já instalado: $bunVersion"
    }
} catch { $bunInstalled = $false }

if (-not $bunInstalled) {
    Write-Warn "Instalando Bun via PowerShell installer..."
    # Bun Windows installer oficial
    irm bun.sh/install.ps1 | iex
    
    # Atualizar PATH para incluir Bun
    $bunPath = "$env:USERPROFILE\\.bun\\bin"
    if (Test-Path $bunPath) {
        $env:Path = "$bunPath;$env:Path"
        $bunVersion = & "$bunPath\\bun.exe" --version 2>$null
        Write-Ok "Bun instalado: $bunVersion"
    } else {
        Write-Err "Bun não foi instalado corretamente."
        exit 1
    }
}

# -------------------------------------------------------
# 5. Instalar gqwen-auth
# -------------------------------------------------------
Write-Step "Instalando gqwen-auth..."
bun install -g gqwen-auth
if ($LASTEXITCODE -ne 0) {
    Write-Err "Falha ao instalar gqwen-auth."
    exit 1
}
Write-Ok "gqwen-auth instalado."

# -------------------------------------------------------
# 6. Instalar OpenClaude
# -------------------------------------------------------
Write-Step "Instalando OpenClaude..."
npm install -g @gitlawb/openclaude
if ($LASTEXITCODE -ne 0) {
    Write-Err "Falha ao instalar OpenClaude."
    exit 1
}
Write-Ok "OpenClaude instalado."

# -------------------------------------------------------
# 7. Configurar variáveis de ambiente (usuário)
# -------------------------------------------------------
Write-Step "Configurando variáveis de ambiente..."
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_USE_OPENAI", "1", "User")
[System.Environment]::SetEnvironmentVariable("OPENAI_BASE_URL", "http://localhost:3099/v1", "User")
[System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "gqwen-proxy", "User")
[System.Environment]::SetEnvironmentVariable("OPENAI_MODEL", "qwen3-coder-plus", "User")

# Aplicar na sessão atual
$env:CLAUDE_CODE_USE_OPENAI = "1"
$env:OPENAI_BASE_URL = "http://localhost:3099/v1"
$env:OPENAI_API_KEY = "gqwen-proxy"
$env:OPENAI_MODEL = "qwen3-coder-plus"

Write-Ok "Variáveis de ambiente configuradas."

# -------------------------------------------------------
# 8. Login OAuth e iniciar proxy
# -------------------------------------------------------
Write-Step "Verificando conta Qwen..."
$accountList = gqwen list 2>$null | Out-String
$accountCount = ($accountList | Select-String -Pattern '^\\s*[0-9]+\\s+[a-f0-9]+' -AllMatches).Matches.Count

if ($accountCount -gt 0) {
    Write-Ok "$accountCount conta(s) Qwen já cadastrada(s)."
} else {
    Write-Host ""
    Write-Warn "Nenhuma conta Qwen encontrada."
    Write-Host ""
    Write-Host "  -------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Ação necessária: login no browser" -ForegroundColor Yellow
    Write-Host "  O browser será aberto para autenticação OAuth no qwen.ai."
    Write-Host "  Faça login com sua conta gratuita (não precisa de cartão)."
    Write-Host "  -------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Pressione Ctrl+C após ver 'Authorization successful!'" -ForegroundColor Yellow
    Write-Host ""
    
    gqwen add
}

Write-Step "Iniciando proxy gqwen-auth..."
gqwen serve on 2>$null
Start-Sleep -Seconds 2

# -------------------------------------------------------
# 9. Testar endpoint
# -------------------------------------------------------
Write-Step "Testando endpoint do proxy..."
$maxTries = 10
$try = 0
$proxyOk = $false

while ($try -lt $maxTries) {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3099/v1/models" -UseBasicParsing -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            $proxyOk = $true
            break
        }
    } catch {}
    $try++
    if ($try -lt $maxTries) { Start-Sleep -Seconds 1 }
}

if ($proxyOk) {
    Write-Ok "Proxy respondendo em http://localhost:3099/v1"
} else {
    Write-Err "Proxy não respondeu após ${maxTries}s."
    Write-Warn "Tente manualmente: gqwen serve on"
    exit 1
}

# -------------------------------------------------------
# 10. Criar funções PowerShell para uso diário
# -------------------------------------------------------
Write-Step "Criando comandos qoc-* no PowerShell..."

$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }

$aliases = @'

# --- setup-gq-oc aliases (Windows nativo) ---
function qoc-start {
    param([string]$ProjectPath = "")
    
    # Verificar se proxy está rodando
    try {
        $null = Invoke-WebRequest -Uri "http://localhost:3099/v1/models" -UseBasicParsing -TimeoutSec 1 -ErrorAction Stop
    } catch {
        Write-Host "Iniciando proxy gqwen-auth..." -ForegroundColor Cyan
        gqwen serve on
        Start-Sleep -Seconds 2
    }
    
    if ($ProjectPath -ne "") {
        Set-Location $ProjectPath
    }
    
    Write-Host "Modelo: $env:OPENAI_MODEL" -ForegroundColor Cyan
    openclaude
}

function qoc-stop    { gqwen serve off }
function qoc-status  { gqwen status }
function qoc-doctor  {
    Write-Host "`n==================================================" -ForegroundColor Cyan
    Write-Host "   setup-gq-oc  doctor (Windows)" -ForegroundColor Cyan
    Write-Host "==================================================" -ForegroundColor Cyan
    
    Write-Host "`n[ Sistema ]" -ForegroundColor Bold
    Write-Host "  · SO: Windows $(${env:COMPUTERNAME})"
    
    Write-Host "`n[ Ferramentas ]" -ForegroundColor Bold
    if (Get-Command bun -ErrorAction SilentlyContinue) {
        Write-Host "  ✓ Bun: $(bun --version)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Bun não encontrado" -ForegroundColor Red
    }
    
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-Host "  ✓ Node.js: $(node --version)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Node.js não encontrado" -ForegroundColor Red
    }
    
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        Write-Host "  ✓ npm: $(npm --version)" -ForegroundColor Green
    } else {
        Write-Host "  ✗ npm não encontrado" -ForegroundColor Red
    }
    
    Write-Host "`n[ gqwen-auth ]" -ForegroundColor Bold
    if (Get-Command gqwen -ErrorAction SilentlyContinue) {
        Write-Host "  ✓ gqwen-auth instalado" -ForegroundColor Green
        $accountList = gqwen list 2>$null | Out-String
        $accountCount = ($accountList | Select-String -Pattern '^\\s*[0-9]+\\s+[a-f0-9]+' -AllMatches).Matches.Count
        if ($accountCount -gt 0) {
            Write-Host "  ✓ $accountCount conta(s) Qwen cadastrada(s)" -ForegroundColor Green
        } else {
            Write-Host "  ✗ Nenhuma conta Qwen" -ForegroundColor Red
        }
    } else {
        Write-Host "  ✗ gqwen-auth não encontrado" -ForegroundColor Red
    }
    
    Write-Host "`n[ Proxy ]" -ForegroundColor Bold
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3099/v1/models" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        Write-Host "  ✓ Proxy rodando em http://localhost:3099/v1" -ForegroundColor Green
    } catch {
        Write-Host "  ✗ Proxy não responde" -ForegroundColor Red
    }
    
    Write-Host "`n[ OpenClaude ]" -ForegroundColor Bold
    if (Get-Command openclaude -ErrorAction SilentlyContinue) {
        Write-Host "  ✓ openclaude instalado" -ForegroundColor Green
    } else {
        Write-Host "  ✗ openclaude não encontrado" -ForegroundColor Red
    }
    
    Write-Host "`n[ Variáveis de Ambiente ]" -ForegroundColor Bold
    if ($env:CLAUDE_CODE_USE_OPENAI -eq "1") {
        Write-Host "  ✓ CLAUDE_CODE_USE_OPENAI=1" -ForegroundColor Green
    } else {
        Write-Host "  ✗ CLAUDE_CODE_USE_OPENAI não definido" -ForegroundColor Red
    }
    
    if ($env:OPENAI_BASE_URL) {
        Write-Host "  ✓ OPENAI_BASE_URL=$env:OPENAI_BASE_URL" -ForegroundColor Green
    } else {
        Write-Host "  ✗ OPENAI_BASE_URL não definido" -ForegroundColor Red
    }
    
    if ($env:OPENAI_MODEL) {
        Write-Host "  ✓ OPENAI_MODEL=$env:OPENAI_MODEL" -ForegroundColor Green
    } else {
        Write-Host "  ⚠  OPENAI_MODEL não definido (padrão: qwen3-coder-plus)" -ForegroundColor Yellow
    }
    
    Write-Host ""
}
# --- fim setup-gq-oc ---
'@

$currentProfile = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($null -eq $currentProfile -or -not $currentProfile.Contains('setup-gq-oc aliases')) {
    Add-Content -Path $PROFILE -Value $aliases
    Write-Ok "Comandos qoc-* adicionados ao perfil PowerShell."
} else {
    Write-Ok "Comandos qoc-* já presentes no perfil PowerShell."
}

# -------------------------------------------------------
# Concluído
# -------------------------------------------------------
Write-Host ""
Write-Host "  +------------------------------------------+" -ForegroundColor Green
Write-Host "  |   ✓  Setup concluído! (Windows nativo)  |" -ForegroundColor Green
Write-Host "  +------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "  Abra um novo terminal PowerShell e use:" -ForegroundColor Cyan
Write-Host "    qoc-start              # inicia proxy + OpenClaude aqui" -ForegroundColor White
Write-Host "    qoc-start C:\\meu-app   # especifica um projeto" -ForegroundColor White
Write-Host "    qoc-stop               # para o proxy" -ForegroundColor White
Write-Host "    qoc-status             # quota e tokens" -ForegroundColor White
Write-Host "    qoc-doctor             # diagnostico" -ForegroundColor White
Write-Host ""
Write-Host "  Variáveis de ambiente configuradas permanentemente." -ForegroundColor Gray
Write-Host "  Para alterar modelo: `$env:OPENAI_MODEL='qwen3-coder-flash'" -ForegroundColor Gray
Write-Host ""
