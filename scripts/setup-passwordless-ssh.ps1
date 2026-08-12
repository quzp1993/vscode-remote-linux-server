[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Hosts,

    [string]$PublicKeyPath = "$env:USERPROFILE\.ssh\id_ed25519.pub",
    [string]$PrivateKeyPath = "$env:USERPROFILE\.ssh\id_ed25519"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$publicKey = (Get-Content -LiteralPath $PublicKeyPath -Raw).Trim()
if ([string]::IsNullOrWhiteSpace($publicKey)) {
    throw "Public key is empty: $PublicKeyPath"
}

$publicKeyBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($publicKey))

foreach ($hostName in $Hosts) {
    Write-Output ""
    Write-Output "Configuring passwordless SSH for $hostName ..."

    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    ssh -i $PrivateKeyPath -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 $hostName "echo key_login_already_works" *> $null
    $keyLoginAlreadyWorks = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $previousErrorActionPreference

    if ($keyLoginAlreadyWorks) {
        Write-Output "Key login already works for $hostName."
        continue
    }

    $remoteCommand = @'
set -e
umask 077
key_b64='__PUBLIC_KEY_BASE64__'
key="$(printf '%s' "$key_b64" | base64 -d)"
mkdir -p ~/.ssh
touch ~/.ssh/authorized_keys
grep -qxF "$key" ~/.ssh/authorized_keys || printf '%s\n' "$key" >> ~/.ssh/authorized_keys
chmod go-w ~
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
command -v restorecon >/dev/null 2>&1 && restorecon -R ~/.ssh >/dev/null 2>&1 || true
grep -qxF "$key" ~/.ssh/authorized_keys && echo __PUBLIC_KEY_INSTALLED__
'@.Replace("__PUBLIC_KEY_BASE64__", $publicKeyBase64)

    Write-Output "Enter the SSH password for $hostName when prompted."
    ssh $hostName $remoteCommand
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install public key on $hostName."
    }

    Write-Output "Verifying key login..."
    ssh -i $PrivateKeyPath -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=10 $hostName "echo __SSH_KEY_LOGIN_READY__"
    if ($LASTEXITCODE -ne 0) {
        throw "Key login verification failed for $hostName."
    }
}

Write-Output ""
Write-Output "Passwordless SSH is ready for all requested hosts."

