# env-manager.ps1 - Encrypted .env manager using Windows DPAPI
# Place at: ~/dev/pwsh-env/env-manager.ps1
# Usage: . .\env-manager.ps1

$script:EnvFile = Join-Path $PSScriptRoot ".env.encrypted"

function _Read-EnvStore {
    if (-not (Test-Path $script:EnvFile)) { return @{} }
    try {
        $raw = Get-Content $script:EnvFile -Raw
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        $json = $raw | ConvertFrom-Json
        $store = @{}
        foreach ($prop in $json.PSObject.Properties) {
            $store[$prop.Name] = $prop.Value
        }
        return $store
    } catch {
        Write-Warning "Could not read .env.encrypted: $_"
        return @{}
    }
}

function _Write-EnvStore {
    param([hashtable]$store)
    $store | ConvertTo-Json -Depth 3 | Set-Content $script:EnvFile -Force
}

function _Encrypt-String {
    param([string]$plaintext)
    $secure = ConvertTo-SecureString $plaintext -AsPlainText -Force
    return ($secure | ConvertFrom-SecureString)
}

function _Decrypt-String {
    param([string]$ciphertext)
    try {
        $secure = $ciphertext | ConvertTo-SecureString
        $ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToGlobalAllocUnicode($secure)
        $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
        [System.Runtime.InteropServices.Marshal]::ZeroFreeGlobalAllocUnicode($ptr)
        return $plain
    } catch {
        Write-Error "Decryption failed. Were these secrets created by a different user/machine?"
        return $null
    }
}

function env-set {
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value
    )
    $store = _Read-EnvStore
    $store[$Key] = _Encrypt-String $Value
    _Write-EnvStore $store
    Write-Host "  Set $Key" -ForegroundColor Green
}

function env-get {
    param([Parameter(Mandatory)][string]$Key)
    $store = _Read-EnvStore
    if (-not $store.ContainsKey($Key)) {
        Write-Host "  Key not found: $Key" -ForegroundColor Red
        return
    }
    $val = _Decrypt-String $store[$Key]
    Write-Host "  $Key = $val" -ForegroundColor Cyan
}

function env-load {
    $store = _Read-EnvStore
    $count = 0
    foreach ($kv in $store.GetEnumerator()) {
        $val = _Decrypt-String $kv.Value
        if ($val) {
            Set-Item "env:$($kv.Key)" $val
            $count++
        }
    }
    Write-Host "  Loaded $count secrets into session" -ForegroundColor Green
}

function env-list {
    $store = _Read-EnvStore
    if ($store.Count -eq 0) {
        Write-Host "  No secrets stored yet. Use: env-set KEY VALUE" -ForegroundColor Yellow
        return
    }
    Write-Host ""
    Write-Host "  Stored secrets ($($store.Count)):" -ForegroundColor Cyan
    foreach ($key in ($store.Keys | Sort-Object)) {
        Write-Host "    $key" -ForegroundColor White
    }
    Write-Host ""
}

function env-delete {
    param([Parameter(Mandatory)][string]$Key)
    $store = _Read-EnvStore
    if (-not $store.ContainsKey($Key)) {
        Write-Host "  Key not found: $Key" -ForegroundColor Red
        return
    }
    $store.Remove($Key)
    _Write-EnvStore $store
    Write-Host "  Deleted $Key" -ForegroundColor Green
}

function env-edit {
    while ($true) {
        Write-Host ""
        Write-Host "  .env Manager" -ForegroundColor Cyan
        Write-Host "  [1] List keys"
        Write-Host "  [2] Set a key"
        Write-Host "  [3] Get a key"
        Write-Host "  [4] Delete a key"
        Write-Host "  [5] Load all into session"
        Write-Host "  [q] Quit"
        Write-Host ""
        $choice = Read-Host "  Choice"
        switch ($choice) {
            "1" { env-list }
            "2" { $k = Read-Host "  Key"; $v = Read-Host "  Value"; env-set $k $v }
            "3" { $k = Read-Host "  Key"; env-get $k }
            "4" { $k = Read-Host "  Key"; env-delete $k }
            "5" { env-load }
            "q" { break }
        }
        if ($choice -eq "q") { break }
    }
}

function env-help {
    Write-Host ""
    Write-Host "  env-manager commands:" -ForegroundColor Cyan
    Write-Host "  env-set KEY VALUE   - Add or update a secret"
    Write-Host "  env-get KEY         - Decrypt and show one secret"
    Write-Host "  env-load            - Load all secrets into session"
    Write-Host "  env-list            - Show all key names"
    Write-Host "  env-delete KEY      - Remove a secret"
    Write-Host "  env-edit            - Interactive menu"
    Write-Host ""
}

env-load
Write-Host "  env-manager loaded. Run env-help to see commands." -ForegroundColor DarkGray
