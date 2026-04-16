#Requires -Version 5.1
<#
.SYNOPSIS
    setup-gq-oc  Bootstrap Windows Nativo
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

# -------------------------------------------------------
# Refresh PATH da sesso atual
# -------------------------------------------------------
function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

function Get-RepoRoot {
    if ($env:SETUP_GQ_OC_REPO_DIR) {
        $candidate = $env:SETUP_GQ_OC_REPO_DIR
        if (Test-Path (Join-Path $candidate 'scripts\patch-gqwen-auth.mjs')) {
            return (Resolve-Path $candidate).Path
        }
    }

    if ($PSCommandPath) {
        $candidate = Split-Path (Split-Path $PSCommandPath -Parent) -Parent
        if (Test-Path (Join-Path $candidate 'scripts\patch-gqwen-auth.mjs')) {
            return (Resolve-Path $candidate).Path
        }
    }

    return $null
}

function Invoke-GqwenPatch {
    Write-Step "Aplicando patch de compatibilidade no gqwen-auth..."

    $repoRoot = Get-RepoRoot
    if ($repoRoot) {
        & node (Join-Path $repoRoot 'scripts\patch-gqwen-auth.mjs')
    } else {
        $patchScript = @'
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const bunInstall = process.env.BUN_INSTALL || path.join(os.homedir(), ".bun");
const targets = [
  path.join(bunInstall, "install", "global", "node_modules", "gqwen-auth", "dist", "gqwen"),
  path.join(
    bunInstall,
    "install",
    "global",
    "node_modules",
    "gqwen-auth",
    "node_modules",
    "gqwen-auth",
    "dist",
    "gqwen",
  ),
];

const patchMarker = "pendingSessionsGcTimer.unref?.();";
const patchPattern =
  /var pendingSessions = new Map;\r?\nsetInterval\(\(\) => \{\r?\n([\s\S]*?)\r?\n\}, 10 \* 60 \* 1000\);/;

let discovered = 0;
let patched = 0;
let alreadyPatched = 0;

for (const target of targets) {
  if (!fs.existsSync(target)) {
    continue;
  }

  discovered += 1;
  const original = fs.readFileSync(target, "utf8");

  if (original.includes(patchMarker)) {
    alreadyPatched += 1;
    console.log(`[ok] already patched: ${target}`);
    continue;
  }

  const newline = original.includes("\r\n") ? "\r\n" : "\n";
  const next = original.replace(patchPattern, (_match, body) =>
    [
      "var pendingSessions = new Map;",
      "var pendingSessionsGcTimer = setInterval(() => {",
      body,
      "}, 10 * 60 * 1000);",
      "pendingSessionsGcTimer.unref?.();",
    ].join(newline),
  );

  if (next === original) {
    console.error(`[err] patch target not found: ${target}`);
    continue;
  }

  fs.writeFileSync(target, next, "utf8");
  patched += 1;
  console.log(`[ok] patched: ${target}`);
}

if (discovered === 0) {
  console.error("[err] gqwen-auth not found under Bun global directory.");
  process.exit(1);
}

if (patched === 0 && alreadyPatched === 0) {
  console.error("[err] gqwen-auth found, but patch could not be applied.");
  process.exit(1);
}

console.log(`[done] gqwen-auth patch ready (${patched} changed, ${alreadyPatched} already patched).`);
'@
        $patchScript | node -
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Err "Falha ao aplicar patch no gqwen-auth."
        exit 1
    }

    Write-Ok "Patch gqwen-auth aplicado."
}

function Test-GqwenAccounts {
    Write-Step "Validando conectividade das contas Qwen..."
    $testOutput = (& cmd.exe /d /c "gqwen test 2>&1" | Out-String)
    if ($testOutput.Trim()) {
        Write-Host $testOutput.TrimEnd()
    }

    return ([regex]::Matches($testOutput, '(^|\s)OK(\s|$)')).Count
}

function Count-QwenAccounts {
    param([string]$AccountList)

    return ([regex]::Matches($AccountList, '(?m)^\s*[0-9]+\s+[a-f0-9]+')).Count
}

Write-Banner

# -------------------------------------------------------
# 1. Verificar privilgios de Administrador
# -------------------------------------------------------
Write-Step "Verificando privilgios..."
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Execute o PowerShell como Administrador."
    Write-Host "  Clique com botao direito no PowerShell > 'Executar como administrador'"
    Write-Host "  Depois rode o comando novamente." -ForegroundColor Yellow
    exit 1
}
Write-Ok "Rodando como Administrador."

# -------------------------------------------------------
# 2. Verificar verso do Windows
# -------------------------------------------------------
Write-Step "Verificando compatibilidade do Windows..."
$build = [System.Environment]::OSVersion.Version.Build
$winVer = (Get-ItemProperty 'HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion').DisplayVersion 2>$null
if ($null -eq $winVer) { $winVer = "Windows $([System.Environment]::OSVersion.Version)" }

if ($build -lt 10240) {
    Write-Err "Windows build $build detectado. Requer Windows 10 build 10240+ ou Windows 11."
    exit 1
}
Write-Ok "$winVer (build $build) - compativel."

# -------------------------------------------------------
# 3. Instalar Node.js via winget
# -------------------------------------------------------
Write-Step "Verificando Node.js..."
Refresh-Path
$nodeInstalled = $false
try {
    $nodeVersion = node --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $nodeInstalled = $true
        Write-Ok "Node.js ja instalado: $nodeVersion"
    }
} catch { $nodeInstalled = $false }

if (-not $nodeInstalled) {
    Write-Warn "Instalando Node.js via winget..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements -e
        
        # Refresh PATH e adicionar caminhos comuns do Node.js
        Refresh-Path
        $programFilesX86 = [System.Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
        $nodePaths = @(
            "$env:ProgramFiles\\nodejs",
            "$programFilesX86\\nodejs",
            "$env:APPDATA\\npm"
        )
        foreach ($p in $nodePaths) {
            if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) {
                $env:Path = $p + ";" + $env:Path
            }
        }
        
        Start-Sleep -Seconds 2
        
        # Verificar se node esta acessivel agora
        try {
            $nodeVersion = node --version 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Node.js instalado: $nodeVersion"
            } else {
                throw "Node nao encontrado no PATH"
            }
        } catch {
            Write-Err "Node.js foi instalado mas nao esta acessivel."
            Write-Host "  Execute em um novo terminal: node --version" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Err "winget nao encontrado. Instale Node.js manualmente: https://nodejs.org"
        exit 1
    }
}

try {
    $npmVersion = npm --version 2>$null
    Write-Ok "npm $npmVersion"
} catch {
    Write-Err "npm nao encontrado no PATH."
    exit 1
}

# -------------------------------------------------------
# 4. Instalar Bun
# -------------------------------------------------------
Write-Step "Verificando Bun..."
$bunInstalled = $false
try {
    $bunVersion = bun --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        $bunInstalled = $true
        Write-Ok "Bun ja instalado: $bunVersion"
    }
} catch { $bunInstalled = $false }

if (-not $bunInstalled) {
    Write-Warn "Instalando Bun via PowerShell installer..."
    # Bun Windows installer oficial
    irm bun.sh/install.ps1 | iex
    
    # Atualizar PATH para incluir Bun
    $bunPath = "$env:USERPROFILE\\.bun\\bin"
    if (Test-Path $bunPath) {
        $env:Path = $bunPath + ";" + $env:Path
        $bunVersion = & "$bunPath\\bun.exe" --version 2>$null
        Write-Ok "Bun instalado: $bunVersion"
    } else {
        Write-Err "Bun nao foi instalado corretamente."
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
# 6b. Patch gqwen-auth
# -------------------------------------------------------
Invoke-GqwenPatch

# -------------------------------------------------------
# 7. Configurar variveis de ambiente (usurio)
# -------------------------------------------------------
Write-Step "Configurando variveis de ambiente..."
[System.Environment]::SetEnvironmentVariable("CLAUDE_CODE_USE_OPENAI", "1", "User")
[System.Environment]::SetEnvironmentVariable("OPENAI_BASE_URL", "http://localhost:3099/v1", "User")
[System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "gqwen-proxy", "User")
[System.Environment]::SetEnvironmentVariable("OPENAI_MODEL", "qwen3-coder-plus", "User")

# Aplicar na sesso atual
$env:CLAUDE_CODE_USE_OPENAI = "1"
$env:OPENAI_BASE_URL = "http://localhost:3099/v1"
$env:OPENAI_API_KEY = "gqwen-proxy"
$env:OPENAI_MODEL = "qwen3-coder-plus"

Write-Ok "Variaveis de ambiente configuradas."

# -------------------------------------------------------
# 8. Login OAuth e iniciar proxy
# -------------------------------------------------------
Write-Step "Verificando conta Qwen..."
$accountList = gqwen list 2>$null | Out-String
$accountCount = Count-QwenAccounts $accountList
$validAccountCount = 0

if ($accountCount -gt 0) {
    Write-Ok "$accountCount conta(s) Qwen ja cadastrada(s)."
    $validAccountCount = Test-GqwenAccounts

    if ($validAccountCount -gt 0) {
        Write-Ok "$validAccountCount conta(s) valida(s) para uso."
    } else {
        Write-Warn "Contas cadastradas, mas nenhuma respondeu com sucesso."
    }
}

if ($accountCount -eq 0 -or $validAccountCount -eq 0) {
    Write-Host ""
    if ($accountCount -eq 0) {
        Write-Warn "Nenhuma conta Qwen encontrada."
    } else {
        Write-Warn "Necessario renovar autenticacao no Qwen."
    }
    Write-Host ""
    Write-Host "  -------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Acao necessaria: login no browser" -ForegroundColor Yellow
    Write-Host "  O browser sera aberto para autenticacao OAuth no qwen.ai."
    Write-Host "  Faca login com sua conta gratuita (nao precisa de cartao)."
    Write-Host "  -------------------------------------------" -ForegroundColor Cyan
    Write-Host ""

    gqwen add

    $validAccountCount = Test-GqwenAccounts
    if ($validAccountCount -eq 0) {
        Write-Err "Login concluido, mas nenhuma conta ficou valida."
        exit 1
    }

    Write-Ok "$validAccountCount conta(s) valida(s) para uso."
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
    Write-Err "Proxy nao respondeu apos ${maxTries}s."
    Write-Warn "Tente manualmente: gqwen serve on"
    exit 1
}

# -------------------------------------------------------
# 10. Criar funes PowerShell para uso dirio
# -------------------------------------------------------
Write-Step "Criando comandos qoc-* no PowerShell..."

$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }

$aliases = @'

# --- setup-gq-oc aliases (Windows nativo) ---
function qoc-start {
    param([string]$ProjectPath = "")
    
    # Verificar se proxy est rodando
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
    
    Write-Host "`n[ Sistema ]" -ForegroundColor Cyan
    Write-Host "   SO: Windows $(${env:COMPUTERNAME})"
    
    Write-Host "`n[ Ferramentas ]" -ForegroundColor Cyan
    if (Get-Command bun -ErrorAction SilentlyContinue) {
        Write-Host "   Bun: $(bun --version)" -ForegroundColor Green
    } else {
        Write-Host "   Bun nao encontrado" -ForegroundColor Red
    }
    
    if (Get-Command node -ErrorAction SilentlyContinue) {
        Write-Host "   Node.js: $(node --version)" -ForegroundColor Green
    } else {
        Write-Host "   Node.js nao encontrado" -ForegroundColor Red
    }
    
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        Write-Host "   npm: $(npm --version)" -ForegroundColor Green
    } else {
        Write-Host "   npm nao encontrado" -ForegroundColor Red
    }
    
    Write-Host "`n[ gqwen-auth ]" -ForegroundColor Cyan
    if (Get-Command gqwen -ErrorAction SilentlyContinue) {
        Write-Host "   gqwen-auth instalado" -ForegroundColor Green
        $accountList = gqwen list 2>$null | Out-String
        $accountCount = ([regex]::Matches($accountList, '(?m)^\s*[0-9]+\s+[a-f0-9]+')).Count
        if ($accountCount -gt 0) {
            Write-Host "   $accountCount conta(s) Qwen cadastrada(s)" -ForegroundColor Green
        } else {
            Write-Host "   Nenhuma conta Qwen" -ForegroundColor Red
        }
    } else {
        Write-Host "   gqwen-auth nao encontrado" -ForegroundColor Red
    }
    
    Write-Host "`n[ Proxy ]" -ForegroundColor Cyan
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:3099/v1/models" -UseBasicParsing -TimeoutSec 2 -ErrorAction Stop
        Write-Host "   Proxy rodando em http://localhost:3099/v1" -ForegroundColor Green
    } catch {
        Write-Host "   Proxy nao responde" -ForegroundColor Red
    }
    
    Write-Host "`n[ OpenClaude ]" -ForegroundColor Cyan
    if (Get-Command openclaude -ErrorAction SilentlyContinue) {
        Write-Host "   openclaude instalado" -ForegroundColor Green
    } else {
        Write-Host "   openclaude nao encontrado" -ForegroundColor Red
    }
    
    Write-Host "`n[ Variaveis de Ambiente ]" -ForegroundColor Cyan
    if ($env:CLAUDE_CODE_USE_OPENAI -eq "1") {
        Write-Host "   CLAUDE_CODE_USE_OPENAI=1" -ForegroundColor Green
    } else {
        Write-Host "   CLAUDE_CODE_USE_OPENAI nao definido" -ForegroundColor Red
    }
    
    if ($env:OPENAI_BASE_URL) {
        Write-Host "   OPENAI_BASE_URL=$env:OPENAI_BASE_URL" -ForegroundColor Green
    } else {
        Write-Host "   OPENAI_BASE_URL nao definido" -ForegroundColor Red
    }
    
    if ($env:OPENAI_MODEL) {
        Write-Host "   OPENAI_MODEL=$env:OPENAI_MODEL" -ForegroundColor Green
    } else {
        Write-Host "    OPENAI_MODEL nao definido (padrao: qwen3-coder-plus)" -ForegroundColor Yellow
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
    Write-Ok "Comandos qoc-* ja presentes no perfil PowerShell."
}

# -------------------------------------------------------
# Concludo
# -------------------------------------------------------
Write-Host ""
Write-Host "  +------------------------------------------+" -ForegroundColor Green
Write-Host "  |   OK  Setup concluido! (Windows nativo) |" -ForegroundColor Green
Write-Host "  +------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "  Abra um novo terminal PowerShell e use:" -ForegroundColor Cyan
Write-Host "    qoc-start              # inicia proxy + OpenClaude aqui" -ForegroundColor White
Write-Host "    qoc-start C:\\meu-app   # especifica um projeto" -ForegroundColor White
Write-Host "    qoc-stop               # para o proxy" -ForegroundColor White
Write-Host "    qoc-status             # quota e tokens" -ForegroundColor White
Write-Host "    qoc-doctor             # diagnostico" -ForegroundColor White
Write-Host ""
Write-Host "  Variaveis de ambiente configuradas permanentemente." -ForegroundColor Gray
Write-Host "  Para alterar modelo: `$env:OPENAI_MODEL='qwen3-coder-flash'" -ForegroundColor Gray
Write-Host ""
