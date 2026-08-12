[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SshTarget,

    [string]$PublicKeyPath = "$env:USERPROFILE\.ssh\id_ed25519.pub"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$publicKeyBase64 = ""
if (Test-Path -LiteralPath $PublicKeyPath) {
    $publicKey = (Get-Content -LiteralPath $PublicKeyPath -Raw).Trim()
    if (-not [string]::IsNullOrWhiteSpace($publicKey)) {
        $publicKeyBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($publicKey))
    }
}

$remoteCommand = @'
set -u
echo __BASIC__
whoami
id
printf 'HOME=%s\n' "$HOME"
pwd
cat /etc/redhat-release 2>/dev/null || cat /etc/os-release 2>/dev/null | head -n 5 || true

echo __SSHD_EFFECTIVE_CONFIG__
(sshd -T 2>/dev/null || /usr/sbin/sshd -T 2>/dev/null || true) | egrep '^(pubkeyauthentication|authorizedkeysfile|strictmodes|passwordauthentication|usepam|authorizedkeyscommand|authorizedkeyscommanduser)' || true

echo __PATH_PERMISSIONS__
ls -ld ~ ~/.ssh ~/.ssh/authorized_keys 2>&1 || true
stat -c '%U:%G %a %n' ~ ~/.ssh ~/.ssh/authorized_keys 2>&1 || true
namei -l ~/.ssh/authorized_keys 2>&1 || true

echo __SELINUX__
getenforce 2>/dev/null || true
getsebool use_nfs_home_dirs 2>/dev/null || true
ls -Zd ~ ~/.ssh ~/.ssh/authorized_keys 2>&1 || true

echo __AUTHORIZED_KEYS_MATCH__
key_b64='__PUBLIC_KEY_BASE64__'
if [ -n "$key_b64" ] && [ -f ~/.ssh/authorized_keys ]; then
  key="$(printf '%s' "$key_b64" | base64 -d)"
  grep -nF "$key" ~/.ssh/authorized_keys >/dev/null 2>&1 && echo PUBLIC_KEY_PRESENT || echo PUBLIC_KEY_MISSING
else
  echo PUBLIC_KEY_NOT_CHECKED
fi
wc -l ~/.ssh/authorized_keys 2>&1 || true

echo __AUTHORIZED_KEYS_LAST_LINES__
tail -n 5 ~/.ssh/authorized_keys 2>/dev/null | sed 's/ .*/ .../' || true

echo __DONE_NO_LOGS_READ__
'@.Replace("__PUBLIC_KEY_BASE64__", $publicKeyBase64)

Write-Output "Enter the SSH password for $SshTarget when prompted."
ssh $SshTarget $remoteCommand

