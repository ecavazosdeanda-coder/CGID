param([string]$File, [string]$Name)
$ErrorActionPreference='Stop'
$credentialLines = "protocol=https`nhost=github.com`nusername=ecavazosdeanda-coder`n`n" | git credential fill
$credentialValue = ($credentialLines | Where-Object { $_.StartsWith('password=') }).Substring(9)
$uploadUrl = 'https://uploads.github.com/repos/ecavazosdeanda-coder/CGID/releases/400381621/assets?name=' + [Uri]::EscapeDataString($Name)
$curlConfig = 'header = "Authorization: Bearer ' + $credentialValue + '"'
try {
  $curlConfig | curl.exe --config - --http1.1 --silent --show-error --fail-with-body --max-time 180 -H 'Content-Type: application/octet-stream' -H 'Accept: application/vnd.github+json' --data-binary ('@' + (Resolve-Path $File).Path) $uploadUrl
  if ($LASTEXITCODE -ne 0) { throw 'Upload failed' }
} finally { $credentialLines=$null; $credentialValue=$null; $curlConfig=$null }
