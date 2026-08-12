[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SshTarget,

    [Parameter(Mandatory = $true)]
    [string]$Package
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$resolvedPackage = (Resolve-Path -LiteralPath $Package).Path
$remotePackage = "~/vscode-server-centos7.tar.gz"

Write-Output "Checking remote system: $SshTarget"
ssh $SshTarget "uname -m; cat /etc/redhat-release 2>/dev/null || cat /etc/os-release | head -n 3"
if ($LASTEXITCODE -ne 0) {
    throw "SSH check failed."
}

Write-Output "Uploading VS Code Server package..."
scp $resolvedPackage "$($SshTarget):$remotePackage"
if ($LASTEXITCODE -ne 0) {
    throw "Upload failed."
}

Write-Output "Installing patched VS Code Server..."
$remoteCommand = "set -e; mkdir -p ~/.vscode-server; tar xzf $remotePackage -C ~/.vscode-server --strip-components 1; ~/.vscode-server/code-latest --patch-now; rm -f $remotePackage; echo __VSCODE_SERVER_CENTOS7_READY__"
ssh $SshTarget $remoteCommand
if ($LASTEXITCODE -ne 0) {
    throw "Remote install failed."
}

Write-Output "Done. Connect with VS Code Remote-SSH to $SshTarget."

