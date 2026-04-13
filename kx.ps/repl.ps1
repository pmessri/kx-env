# repl.ps1 - Dev Environment REPL
# Usage: .\repl.ps1

param([switch]$Minimal)

$script:Root        = $PSScriptRoot
$script:HistoryFile = Join-Path $script:Root ".repl_history"
$script:CheatFile   = Join-Path $script:Root "CHEATSHEET.md"
$script:EnvManager  = Join-Path $script:Root "env-manager.ps1"
$script:GenCheat    = Join-Path $script:Root "gen-cheatsheet.ps1"
$script:History     = [System.Collections.Generic.List[string]]::new()

# Load env-manager
if (Test-Path $script:EnvManager) {
    . $script:EnvManager 2>$null
}

# Load history
if (Test-Path $script:HistoryFile) {
    Get-Content $script:HistoryFile | ForEach-Object {
        if ($_) { $script:History.Add($_) }
    }
}

function _Add-History {
    param([string]$cmd)
    if ($cmd -and ($script:History.Count -eq 0 -or $script:History[-1] -ne $cmd)) {
        $script:History.Add($cmd)
        $cmd | Add-Content $script:HistoryFile
    }
}

function _Get-EnvOrDefault {
    param([string]$name, [string]$default = "(none)")
    $val = (Get-Item "env:$name" -ErrorAction SilentlyContinue)
    if ($val) { return $val.Value } else { return $default }
}

function _Banner {
    if ($Minimal) { return }
    Write-Host ""
    Write-Host "  Dev Environment REPL" -ForegroundColor Cyan
    Write-Host "  Type :help for commands, :quit to exit" -ForegroundColor DarkGray
    Write-Host ""
}

function _Prompt {
    $loc  = Split-Path $PWD -Leaf
    $aws  = _Get-EnvOrDefault "AWS_PROFILE" ""
    $venv = _Get-EnvOrDefault "VIRTUAL_ENV" ""
    $ctx  = ""
    if ($aws)  { $ctx += " aws:$aws" }
    if ($venv) { $ctx += " py:$(Split-Path $venv -Leaf)" }

    Write-Host "" 
    Write-Host -NoNewline "  repl " -ForegroundColor Cyan
    Write-Host -NoNewline "$loc" -ForegroundColor White
    if ($ctx) { Write-Host -NoNewline $ctx -ForegroundColor DarkYellow }
    Write-Host -NoNewline " > " -ForegroundColor Green
}

function _Claude-Ask {
    param([string]$prompt)
    $key = _Get-EnvOrDefault "ANTHROPIC_API_KEY" ""
    if (-not $key) { Write-Host "  ANTHROPIC_API_KEY not set. Run: :env load" -ForegroundColor Red; return }
    $body = @{
        model      = "claude-opus-4-5"
        max_tokens = 1024
        messages   = @(@{ role = "user"; content = $prompt })
    } | ConvertTo-Json -Depth 5
    $headers = @{
        "x-api-key"         = $key
        "anthropic-version" = "2023-06-01"
        "content-type"      = "application/json"
    }
    try {
        $resp = Invoke-RestMethod -Uri "https://api.anthropic.com/v1/messages" -Method POST -Headers $headers -Body $body
        Write-Host ""
        Write-Host "  Claude:" -ForegroundColor Cyan
        Write-Host $resp.content[0].text -ForegroundColor White
    } catch {
        Write-Host "  API error: $_" -ForegroundColor Red
    }
}

function _Gemini-Ask {
    param([string]$prompt)
    $key = _Get-EnvOrDefault "GEMINI_API_KEY" ""
    if (-not $key) { Write-Host "  GEMINI_API_KEY not set. Run: :env load" -ForegroundColor Red; return }
    $body = @{ contents = @(@{ parts = @(@{ text = $prompt }) }) } | ConvertTo-Json -Depth 5
    $url  = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$key"
    try {
        $resp = Invoke-RestMethod -Uri $url -Method POST -ContentType "application/json" -Body $body
        Write-Host ""
        Write-Host "  Gemini:" -ForegroundColor Blue
        Write-Host $resp.candidates[0].content.parts[0].text -ForegroundColor White
    } catch {
        Write-Host "  API error: $_" -ForegroundColor Red
    }
}

function _Grok-Ask {
    param([string]$prompt)
    $key = _Get-EnvOrDefault "GROK_API_KEY" ""
    if (-not $key) { Write-Host "  GROK_API_KEY not set. Run: :env load" -ForegroundColor Red; return }
    $body    = @{ model = "grok-beta"; messages = @(@{ role = "user"; content = $prompt }) } | ConvertTo-Json -Depth 5
    $headers = @{ "Authorization" = "Bearer $key"; "Content-Type" = "application/json" }
    try {
        $resp = Invoke-RestMethod -Uri "https://api.x.ai/v1/chat/completions" -Method POST -Headers $headers -Body $body
        Write-Host ""
        Write-Host "  Grok:" -ForegroundColor Magenta
        Write-Host $resp.choices[0].message.content -ForegroundColor White
    } catch {
        Write-Host "  API error: $_" -ForegroundColor Red
    }
}

function _Handle-Meta {
    param([string]$line)
    $parts = $line.TrimStart(":").Split(" ", 2)
    $cmd   = $parts[0].ToLower()
    $arg   = if ($parts.Count -gt 1) { $parts[1] } else { "" }

    switch ($cmd) {
        "help" {
            Write-Host ""
            Write-Host "  REPL Commands" -ForegroundColor Cyan
            Write-Host "  -------------------------------------------------" -ForegroundColor DarkGray
            Write-Host "  :help                  Show this help"
            Write-Host "  :quit  :q              Exit the REPL"
            Write-Host "  :clear                 Clear screen"
            Write-Host ""
            Write-Host "  AI:" -ForegroundColor Yellow
            Write-Host "  :ask PROMPT            Ask Claude"
            Write-Host "  :gem PROMPT            Ask Gemini"
            Write-Host "  :grok PROMPT           Ask Grok"
            Write-Host "  :explain CMD           Ask Claude to explain a command"
            Write-Host "  :fix                   Ask Claude to explain last error"
            Write-Host ""
            Write-Host "  Cheatsheet:" -ForegroundColor Yellow
            Write-Host "  :cs                    View full cheatsheet"
            Write-Host "  :cs TERM               Search cheatsheet"
            Write-Host "  :regen                 Regenerate cheatsheet via AI"
            Write-Host ""
            Write-Host "  Environment:" -ForegroundColor Yellow
            Write-Host "  :env list              List secret key names"
            Write-Host "  :env set KEY VALUE     Add or update a secret"
            Write-Host "  :env get KEY           Decrypt and show a secret"
            Write-Host "  :env load              Load all secrets into session"
            Write-Host "  :ctx                   Show current cloud/AI context"
            Write-Host "  :aws PROFILE           Switch AWS profile"
            Write-Host "  :gcp PROJECT           Switch GCP project"
            Write-Host ""
            Write-Host "  History:" -ForegroundColor Yellow
            Write-Host "  :history               Show last 25 commands"
            Write-Host "  :history N             Show last N commands"
            Write-Host "  -------------------------------------------------" -ForegroundColor DarkGray
            Write-Host ""
        }

        { $_ -in "quit","q","exit" } {
            Write-Host ""
            Write-Host "  Goodbye." -ForegroundColor DarkGray
            Write-Host ""
            return "EXIT"
        }

        { $_ -in "clear","cls" } { Clear-Host }

        "ask" {
            if (-not $arg) { Write-Host "  Usage: :ask your question here" -ForegroundColor Yellow; return }
            _Claude-Ask $arg
        }

        "gem" {
            if (-not $arg) { Write-Host "  Usage: :gem your question here" -ForegroundColor Yellow; return }
            _Gemini-Ask $arg
        }

        "grok" {
            if (-not $arg) { Write-Host "  Usage: :grok your question here" -ForegroundColor Yellow; return }
            _Grok-Ask $arg
        }

        "explain" {
            if (-not $arg) { Write-Host "  Usage: :explain the-command" -ForegroundColor Yellow; return }
            _Claude-Ask "Explain this PowerShell/shell command briefly and clearly: $arg"
        }

        "fix" {
            $lastErr = $Error[0]
            if (-not $lastErr) { Write-Host "  No recent error found." -ForegroundColor Yellow; return }
            _Claude-Ask "I got this PowerShell error. Explain what went wrong and how to fix it: $lastErr"
        }

        "cs" {
            if (-not (Test-Path $script:CheatFile)) {
                Write-Host "  No CHEATSHEET.md yet. Run: :regen" -ForegroundColor Yellow; return
            }
            if ($arg) {
                $matches = Select-String -Path $script:CheatFile -Pattern $arg -CaseSensitive:$false
                if ($matches) { $matches | ForEach-Object { Write-Host "  $($_.Line)" -ForegroundColor White } }
                else { Write-Host "  No matches for: $arg" -ForegroundColor Yellow }
            } else {
                Get-Content $script:CheatFile | more
            }
        }

        "regen" {
            if (Test-Path $script:GenCheat) { & $script:GenCheat }
            else { Write-Host "  gen-cheatsheet.ps1 not found in $script:Root" -ForegroundColor Red }
        }

        "env" {
            $envParts = $arg.Split(" ", 3)
            $envCmd   = $envParts[0].ToLower()
            switch ($envCmd) {
                "list" { env-list }
                "load" { env-load }
                "set"  {
                    if ($envParts.Count -ge 3) { env-set $envParts[1] $envParts[2] }
                    else { Write-Host "  Usage: :env set KEY VALUE" -ForegroundColor Yellow }
                }
                "get"  {
                    if ($envParts.Count -ge 2) { env-get $envParts[1] }
                    else { Write-Host "  Usage: :env get KEY" -ForegroundColor Yellow }
                }
                default { Write-Host "  Unknown: try list / set / get / load" -ForegroundColor Yellow }
            }
        }

        "ctx" {
            Write-Host ""
            Write-Host "  Current Context" -ForegroundColor Cyan
            Write-Host "  ---------------------------------" -ForegroundColor DarkGray
            Write-Host "  AWS Profile  : $(_Get-EnvOrDefault 'AWS_PROFILE')"
            Write-Host "  AWS Region   : $(_Get-EnvOrDefault 'AWS_DEFAULT_REGION')"
            Write-Host "  GCP Project  : $(_Get-EnvOrDefault 'CLOUDSDK_CORE_PROJECT')"
            Write-Host "  Virtual Env  : $(_Get-EnvOrDefault 'VIRTUAL_ENV')"
            $claudeSet = if (_Get-EnvOrDefault "ANTHROPIC_API_KEY" "") { "set" } else { "not set" }
            $gemSet    = if (_Get-EnvOrDefault "GEMINI_API_KEY" "")    { "set" } else { "not set" }
            $grokSet   = if (_Get-EnvOrDefault "GROK_API_KEY" "")      { "set" } else { "not set" }
            Write-Host "  Claude Key   : $claudeSet"
            Write-Host "  Gemini Key   : $gemSet"
            Write-Host "  Grok Key     : $grokSet"
            Write-Host ""
        }

        "aws" {
            if (-not $arg) { Write-Host "  Usage: :aws profile-name" -ForegroundColor Yellow; return }
            $env:AWS_PROFILE = $arg
            Write-Host "  AWS_PROFILE = $arg" -ForegroundColor Cyan
        }

        "gcp" {
            if (-not $arg) { Write-Host "  Usage: :gcp project-name" -ForegroundColor Yellow; return }
            $env:CLOUDSDK_CORE_PROJECT = $arg
            Write-Host "  GCP project = $arg" -ForegroundColor Cyan
        }

        "history" {
            $n = 25
            if ($arg -match '^\d+$') { $n = [int]$arg }
            $recent = $script:History | Select-Object -Last $n
            Write-Host ""
            $i = $script:History.Count - $recent.Count
            foreach ($entry in $recent) {
                Write-Host "  $i  $entry" -ForegroundColor DarkGray
                $i++
            }
            Write-Host ""
        }

        default {
            Write-Host "  Unknown command: :$cmd  (type :help)" -ForegroundColor Yellow
        }
    }
}

# Main loop
_Banner

while ($true) {
    _Prompt
    $line = $null
    try { $line = [Console]::ReadLine() } catch { break }
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    _Add-History $line

    if ($line.TrimStart().StartsWith(":")) {
        $result = _Handle-Meta $line.Trim()
        if ($result -eq "EXIT") { break }
        continue
    }

    try {
        $sb     = [scriptblock]::Create($line)
        $result = & $sb
        if ($null -ne $result) { $result | Format-Table -AutoSize 2>$null }
    } catch {
        Write-Host ""
        Write-Host "  Error: $_" -ForegroundColor Red
        Write-Host "  Tip: type :fix to ask Claude what went wrong" -ForegroundColor DarkGray
    }
}
