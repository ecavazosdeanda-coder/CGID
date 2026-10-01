param([string]$Endpoint, [string]$Method = 'GET', [string]$BodyFile, [string]$OutFile, [string]$UploadFile, [string]$AssetName)
$ErrorActionPreference = 'Stop'
$credentials = "protocol=https`nhost=github.com`nusername=ecavazosdeanda-coder`n`n" | git credential fill
$passwordLine = $credentials | Where-Object { $_.StartsWith('password=') }
if (!$passwordLine) { throw 'No GitHub credential available' }
$headers = @{Authorization = 'Bearer ' + $passwordLine.Substring(9); Accept='application/vnd.github+json'; 'User-Agent'='CGID-release'}
$params = @{Uri='https://api.github.com/repos/ecavazosdeanda-coder/CGID/' + $Endpoint; Headers=$headers; Method=$Method; TimeoutSec=180}
if ($BodyFile) { $params.Body = [System.IO.File]::ReadAllText((Resolve-Path $BodyFile)); $params.ContentType='application/json; charset=utf-8' }
if ($OutFile) { $params.OutFile = $OutFile }
if ($UploadFile) {
    $params.Uri = 'https://uploads.github.com/repos/ecavazosdeanda-coder/CGID/' + $Endpoint + '?name=' + [Uri]::EscapeDataString($AssetName)
    $params.InFile = (Resolve-Path $UploadFile).Path
    $params.ContentType = 'application/octet-stream'
}
try { Invoke-RestMethod @params | ConvertTo-Json -Depth 15 }
finally { $credentials=$null; $passwordLine=$null; $headers=$null }
