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
# Função: resolver nome real da distro Ubuntu no WSL
# Retorna o nome exato registrado (ex: Ubuntu, Ubuntu-24.04, Ubuntu-22.04)
# -------------------------------------------------------
function Get-UbuntuDistroName {
    try {
        # wsl --list --quiet retorna nomes com possíveis caracteres nulos (UTF-16)
        $rawList = wsl --list --quiet 2>&1
        $names = $rawList | ForEach-Object {
            # Remover caracteres nulos e espaços que WSL insere
            ($_ -replace "`0", "").Trim()
        } | Where-Object { $_ -ne "" -and $_ -match "Ubuntu" }
        if ($names) { return ($names | Select-Object -First 1) }
    } catch {}
    return $null
}

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
    $null = wsl --status 2>&1
    if ($LASTEXITCODE -eq 0) { $wslInstalled = $true }
} catch { $wslInstalled = $false }

if (-not $wslInstalled) {
    Write-Warn "WSL2 não encontrado. Instalando..."
    Write-Host "  Isso pode levar alguns minutos..." -ForegroundColor Yellow

    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Null
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Null

    $wslInstallSuccess = $false
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Microsoft.WSL --accept-package-agreements --accept-source-agreements -e 2>$null
        if ($LASTEXITCODE -eq 0) { $wslInstallSuccess = $true }
    }
    if (-not $wslInstallSuccess) {
        wsl --install --no-distribution 2>&1 | Out-Null
    }

    wsl --set-default-version 2 2>&1 | Out-Null
    Write-Ok "WSL2 instalado."
    Write-Warn "ATENÇÃO: Pode ser necessário reiniciar o computador."
    Write-Host ""
    $reboot = Read-Host "  Reiniciar agora para ativar WSL2? [S/n]"
    if ($reboot -ne 'n' -and $reboot -ne 'N') {
        $scriptUrl = "https://raw.githubusercontent.com/edson-guillen/setup-gq-oc/main/bootstrap/windows.ps1"
        $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' `
            -Argument "-NoProfile -ExecutionPolicy Bypass -Command `"irm $scriptUrl | iex`""
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
# 4. Verificar/instalar Ubuntu e resolver nome da distro
# -------------------------------------------------------
Write-Step "Verificando Ubuntu no WSL..."
$distroName = Get-UbuntuDistroName

if (-not $distroName) {
    Write-Warn "Ubuntu não encontrado. Instalando via wsl --install..."

    # Estratégia 1: wsl --install (mais confiável para registrar no WSL)
    $installOk = $false
    try {
        # Tenta instalar silenciosamente; pode abrir janela de inicialização
        $proc = Start-Process -FilePath "wsl.exe" -ArgumentList "--install -d Ubuntu" `
            -PassThru -WindowStyle Normal
        Write-Host "  Instalando Ubuntu... aguarde (pode abrir uma janela)." -ForegroundColor Yellow
        # Aguarda até 3 min
        $proc.WaitForExit(180000) | Out-Null
        $installOk = $true
    } catch {
        $installOk = $false
    }

    # Estratégia 2: winget como fallback
    if (-not $installOk -or -not (Get-UbuntuDistroName)) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            Write-Warn "Tentando via winget..."
            winget install --id Canonical.Ubuntu.2404 --accept-package-agreements --accept-source-agreements -e 2>$null
        }
    }

    # Aguardar registro no WSL (pode demorar alguns segundos após instalação)
    Write-Warn "Aguardando registro da distro no WSL..."
    $waited = 0
    do {
        Start-Sleep -Seconds 3
        $waited += 3
        $distroName = Get-UbuntuDistroName
    } while (-not $distroName -and $waited -lt 60)

    if (-not $distroName) {
        Write-Err "Ubuntu não foi registrado no WSL após instalação."
        Write-Host ""
        Write-Host "  Solução manual:" -ForegroundColor Yellow
        Write-Host "    1. Abra o menu Iniciar, procure 'Ubuntu' e execute-o uma vez" -ForegroundColor Yellow
        Write-Host "       para completar a inicialização (criação de usuário)." -ForegroundColor Yellow
        Write-Host "    2. Depois execute este script novamente." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Ou tente no PowerShell: wsl --install -d Ubuntu" -ForegroundColor Yellow
        exit 1
    }

    Write-Ok "Ubuntu instalado como: '$distroName'"
} else {
    Write-Ok "Ubuntu encontrado: '$distroName'"
}

# -------------------------------------------------------
# 4b. Inicializar a distro se necessário (primeiro uso)
# -------------------------------------------------------
Write-Step "Inicializando distro '$distroName' (primeira execução)..."

# Tentar um comando simples para ver se a distro já foi inicializada
$testInit = wsl -d $distroName -- echo "ok" 2>&1
if ($LASTEXITCODE -ne 0 -or $testInit -notmatch "ok") {
    Write-Warn "Distro precisa de inicialização. Criando usuário padrão automaticamente..."

    # Inicializar sem interação usando --user root
    # Definir usuário padrão como root temporariamente para setup
    wsl -d $distroName --user root -- bash -c "echo 'root:root' | chpasswd 2>/dev/null; echo ok" 2>&1 | Out-Null

    # Verificar novamente
    $testInit2 = wsl -d $distroName --user root -- echo "ok" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Não foi possível inicializar a distro automaticamente."
        Write-Host ""
        Write-Host "  Solução:" -ForegroundColor Yellow
        Write-Host "    1. Abra o menu Iniciar, procure '$distroName' e execute-o" -ForegroundColor Yellow
        Write-Host "    2. Crie um usuário quando solicitado" -ForegroundColor Yellow
        Write-Host "    3. Execute este script novamente" -ForegroundColor Yellow
        exit 1
    }
    Write-Ok "Distro inicializada."
} else {
    Write-Ok "Distro '$distroName' pronta."
}

# Garantir WSL2 para a distro
try { wsl --set-version $distroName 2 2>&1 | Out-Null } catch {}

# -------------------------------------------------------
# 5. Rodar setup Linux dentro do WSL
# -------------------------------------------------------
Write-Step "Executando setup dentro do WSL ($distroName)..."
Write-Host "  Instalando Bun, gqwen-auth, OpenClaude e configurando ambiente..." -ForegroundColor Gray
Write-Host "  Só será necessário fazer login no browser do Qwen." -ForegroundColor Gray
Write-Host ""

$setupScript = @'
set -e
export DEBIAN_FRONTEND=noninteractive

echo "[==>] Atualizando pacotes base..."
sudo apt-get update -qq 2>/dev/null && sudo apt-get install -y -qq curl git unzip 2>/dev/null

REPO_DIR="$HOME/setup-gq-oc"
if [ -d "$REPO_DIR/.git" ]; then
  echo "[==>] Atualizando repositório..."
  git -C "$REPO_DIR" pull --ff-only 2>/dev/null || true
else
  echo "[==>] Clonando repositório..."
  git clone https://github.com/edson-guillen/setup-gq-oc.git "$REPO_DIR"
fi

chmod +x "$REPO_DIR"/scripts/*.sh

echo "[==>] Executando install.sh..."
bash "$REPO_DIR/scripts/install.sh"

echo "[==>] Executando first-run.sh..."
bash "$REPO_DIR/scripts/first-run.sh"
'@

# Escrever script em arquivo temporário no WSL para evitar problemas de escape
$tmpScript = "/tmp/setup-gq-oc-bootstrap.sh"
$setupScript | wsl -d $distroName --user root -- bash -c "cat > $tmpScript && chmod +x $tmpScript"
wsl -d $distroName --user root -- bash $tmpScript

if ($LASTEXITCODE -ne 0) {
    Write-Err "Setup falhou dentro do WSL. Verifique os logs acima."
    Write-Host "  Para depurar: wsl -d $distroName" -ForegroundColor Yellow
    exit 1
}

# -------------------------------------------------------
# 6. Criar funções PowerShell para uso diário
# -------------------------------------------------------
Write-Step "Criando comandos qoc-* no PowerShell..."

$profileDir = Split-Path $PROFILE -Parent
if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Path $PROFILE -Force | Out-Null }

# Usar o nome real da distro nos aliases
$aliases = @"

# --- setup-gq-oc aliases (distro: $distroName) ---
function qoc-start {
    param([string]`$ProjectPath = "")
    if (`$ProjectPath -ne "") {
        `$wslProj = wsl -d $distroName -- wslpath -u "`$ProjectPath" 2>`$null
        if (-not `$wslProj) { `$wslProj = `$ProjectPath }
        wsl -d $distroName -- bash -c "source ~/.qwen-openclaude.env 2>/dev/null; gqwen serve on 2>/dev/null; cd '`$wslProj' && openclaude"
    } else {
        `$wslPath = wsl -d $distroName -- wslpath -u "`$(Get-Location)" 2>`$null
        if (-not `$wslPath) { `$wslPath = "~" }
        wsl -d $distroName -- bash -c "source ~/.qwen-openclaude.env 2>/dev/null; gqwen serve on 2>/dev/null; cd '`$wslPath' && openclaude"
    }
}

function qoc-stop    { wsl -d $distroName -- bash -c "source ~/.qwen-openclaude.env 2>/dev/null; gqwen serve off" }
function qoc-status  { wsl -d $distroName -- bash -c "source ~/.qwen-openclaude.env 2>/dev/null; gqwen status" }
function qoc-doctor  { wsl -d $distroName -- bash ~/setup-gq-oc/scripts/doctor.sh }
# --- fim setup-gq-oc ---
"@

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
Write-Host "  |   OK  Setup concluido!                   |" -ForegroundColor Green
Write-Host "  +------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "  Abra um novo terminal PowerShell e use:" -ForegroundColor Cyan
Write-Host "    qoc-start              # inicia proxy + OpenClaude aqui" -ForegroundColor White
Write-Host "    qoc-start C:\meu-app   # especifica um projeto" -ForegroundColor White
Write-Host "    qoc-stop               # para o proxy" -ForegroundColor White
Write-Host "    qoc-status             # quota e tokens" -ForegroundColor White
Write-Host "    qoc-doctor             # diagnostico" -ForegroundColor White
Write-Host ""
