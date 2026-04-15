#Requires -Version 5.1
<#
.SYNOPSIS
    setup-gq-oc — Bootstrap Windows
    Instala WSL2 + Ubuntu, clona o repo e executa o setup Linux automaticamente.

.USAGE
    # PowerShell como Administrador:
    irm https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/bootstrap/windows.ps1 | iex
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
    Write-Host "  |   🤖  setup-gq-oc  Windows Bootstrap      |" -ForegroundColor Cyan
    Write-Host "  |   gqwen-auth + OpenClaude via WSL2        |" -ForegroundColor Cyan
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
$winVer = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').DisplayVersion 2>$null
if ($null -eq $winVer) { $winVer = "Windows $([System.Environment]::OSVersion.Version)" }

if ($build -lt 19041) {
    Write-Err "Windows build $build detectado. WSL2 requer Windows 10 build 19041+ ou Windows 11."
    Write-Host "  Atualize o Windows e tente novamente." -ForegroundColor Yellow
    exit 1
}
Write-Ok "$winVer (build $build) — compatível."

# -------------------------------------------------------
# 3. Verificar/instalar WSL2
# -------------------------------------------------------
Write-Step "Verificando WSL2..."
$wslInstalled = $false
try {
    $wslVersion = wsl --status 2>&1
    if ($LASTEXITCODE -eq 0) { $wslInstalled = $true }
} catch { $wslInstalled = $false }

if (-not $wslInstalled) {
    Write-Warn "WSL2 não encontrado. Instalando..."
    Write-Host "  Isso pode levar alguns minutos..." -ForegroundColor Yellow

    # Habilitar features necessárias
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null

    # Instalar WSL2 via winget (Windows 11) ou download direto (Windows 10)
    $wslInstallSuccess = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Microsoft.WSL --accept-package-agreements --accept-source-agreements -e 2>$null
        if ($LASTEXITCODE -eq 0) { $wslInstallSuccess = $true }
    }

    if (-not $wslInstallSuccess) {
        Write-Warn "Instalando via wsl --install..."
        wsl --install --no-distribution 2>&1 | Out-Null
    }

    # Definir WSL2 como padrão
    wsl --set-default-version 2 2>&1 | Out-Null

    Write-Ok "WSL2 instalado."
    Write-Warn "ATENÇÃO: Pode ser necessário reiniciar o computador."
    Write-Host ""
    $reboot = Read-Host "  Reiniciar agora para ativar WSL2? [S/n]"
    if ($reboot -ne 'n' -and $reboot -ne 'N') {
        # Criar task scheduled para continuar após reboot
        $scriptUrl = "https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/bootstrap/windows.ps1"
        $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -Command \"irm $scriptUrl | iex\""
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
        Register-ScheduledTask -TaskName 'setup-gq-oc-resume' -Action $action `
            -Trigger $trigger -Principal $principal -Force | Out-Null
        Write-Ok "Task agendada para continuar após o reboot."
        Restart-Computer -Force
    } else {
        Write-Warn "Reinicie manualmente e execute o comando novamente."
        exit 0
    }
}
Write-Ok "WSL2 disponível."

# -------------------------------------------------------
# 4. Verificar/instalar Ubuntu
# -------------------------------------------------------
Write-Step "Verificando Ubuntu no WSL..."
$distros = wsl --list --quiet 2>&1 | Where-Object { $_ -match 'Ubuntu' }

if (-not $distros) {
    Write-Warn "Ubuntu não encontrado. Instalando Ubuntu 24.04..."
    $ubuntuInstalled = $false

    # Tentar via winget primeiro
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Canonical.Ubuntu.2404 --accept-package-agreements --accept-source-agreements -e 2>$null
        if ($LASTEXITCODE -eq 0) { $ubuntuInstalled = $true }
    }

    # Fallback: wsl --install
    if (-not $ubuntuInstalled) {
        wsl --install -d Ubuntu 2>&1 | Out-Null
        $ubuntuInstalled = $true
    }

    Write-Ok "Ubuntu instalado."
    Write-Warn "Aguardando Ubuntu inicializar (primeira execução)..."
    Start-Sleep -Seconds 5

    # Primeira execução: criar usuário padrão não-interativo
    wsl -d Ubuntu -- bash -c "id -u qoc 2>/dev/null || (useradd -m -s /bin/bash qoc && echo 'qoc:qoc' | chpasswd && usermod -aG sudo qoc)" 2>$null
} else {
    Write-Ok "Ubuntu já instalado: $distros"
}

# Garantir WSL2 para Ubuntu
try { wsl --set-version Ubuntu 2 2>&1 | Out-Null } catch {}

# -------------------------------------------------------
# 5. Rodar setup Linux dentro do WSL
# -------------------------------------------------------
Write-Step "Executando setup dentro do WSL (Ubuntu)..."
Write-Host "  Isso instala Bun, gqwen-auth, OpenClaude e configura o ambiente." -ForegroundColor Gray
Write-Host "  Só será necessário fazer login no browser do Qwen." -ForegroundColor Gray
Write-Host ""

$setupCmd = @'
bash -c '
  set -e
  # Atualizar pacotes base
  export DEBIAN_FRONTEND=noninteractive
  sudo apt-get update -qq && sudo apt-get install -y -qq curl git unzip 2>/dev/null

  # Clonar ou atualizar repo
  REPO_DIR="$HOME/setup-gq-oc"
  if [ -d "$REPO_DIR/.git" ]; then
    echo "[==>] Atualizando repositório..."
    git -C "$REPO_DIR" pull --ff-only 2>/dev/null || true
  else
    echo "[==>] Clonando repositório..."
    git clone https://github.com/edson-guillen/setup-gq-oc.git "$REPO_DIR"
  fi

  # Tornar scripts executáveis
  chmod +x "$REPO_DIR"/scripts/*.sh

  # Executar install.sh
  bash "$REPO_DIR/scripts/install.sh"

  # Executar first-run.sh
  bash "$REPO_DIR/scripts/first-run.sh"
'
'@

wsl -d Ubuntu -- bash -c $setupCmd

if ($LASTEXITCODE -ne 0) {
    Write-Err "Setup falhou dentro do WSL. Verifique os logs acima."
    Write-Host "  Para depurar: wsl -d Ubuntu" -ForegroundColor Yellow
    exit 1
}

# -------------------------------------------------------
# 6. Criar aliases PowerShell para uso diário
# -------------------------------------------------------
Write-Step "Criando comandos qoc-* no PowerShell..."

$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }

$aliases = @'

# ─── setup-gq-oc aliases ──────────────────────────────────────
function qoc-start {
    param([string]$ProjectPath = "")
    if ($ProjectPath -ne "") {
        wsl -d Ubuntu -- bash -c "source ~/.qwen-openclaude.env && gqwen serve on 2>/dev/null; cd '$ProjectPath' && openclaude"
    } else {
        $wslPath = wsl -d Ubuntu -- bash -c "wslpath -u '$(Get-Location)'"
        wsl -d Ubuntu -- bash -c "source ~/.qwen-openclaude.env && gqwen serve on 2>/dev/null; cd '$wslPath' && openclaude"
    }
}

function qoc-stop {
    wsl -d Ubuntu -- bash -c "source ~/.qwen-openclaude.env 2>/dev/null; gqwen serve off"
}

function qoc-status {
    wsl -d Ubuntu -- bash -c "source ~/.qwen-openclaude.env 2>/dev/null; gqwen status"
}

function qoc-doctor {
    wsl -d Ubuntu -- bash -c "bash ~/setup-gq-oc/scripts/doctor.sh"
}
# ──────────────────────────────────────────────────────────────
'@

$currentProfile = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
if ($null -eq $currentProfile -or -not $currentProfile.Contains('setup-gq-oc aliases')) {
    Add-Content -Path $PROFILE -Value $aliases
    Write-Ok "Comandos qoc-* adicionados ao perfil PowerShell."
} else {
    Write-Ok "Comandos qoc-* já presentes no perfil PowerShell."
}

# Remover task de reboot se existir
if (Get-ScheduledTask -TaskName 'setup-gq-oc-resume' -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName 'setup-gq-oc-resume' -Confirm:$false
}

# -------------------------------------------------------
# Concluído
# -------------------------------------------------------
Write-Host ""
Write-Host "  +------------------------------------------+" -ForegroundColor Green
Write-Host "  |   ✅  Setup concluído!                   |" -ForegroundColor Green
Write-Host "  +------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "  Abra um novo terminal PowerShell e use:" -ForegroundColor Cyan
Write-Host "    qoc-start              # inicia e abre OpenClaude aqui" -ForegroundColor White
Write-Host "    qoc-start C:\meu-app   # especifica um projeto" -ForegroundColor White
Write-Host "    qoc-stop               # para o proxy" -ForegroundColor White
Write-Host "    qoc-status             # quota e tokens" -ForegroundColor White
Write-Host "    qoc-doctor             # diagnóstico" -ForegroundColor White
Write-Host ""
