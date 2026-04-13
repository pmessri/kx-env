# pwsh-env

PowerShell dev environment configuration — manages secrets, config, AI-generated docs, and an interactive REPL.

## Structure

```
~/dev/pwsh-env/
├── .config                 # Non-secret settings (editor, cloud defaults, paths)
├── .env.encrypted          # DPAPI-encrypted secrets — auto-created by env-manager
├── .cheatsheet-ignore      # Patterns stripped before sending code to AI
├── env-manager.ps1         # Encrypted .env CLI — set/get/load/edit secrets
├── gen-cheatsheet.ps1      # AI agent: reads codebase → generates CHEATSHEET.md
├── repl.ps1                # Interactive REPL with AI assist built in
├── CHEATSHEET.md           # Auto-generated reference (do not edit manually)
└── README.md               # This file
```

## Quick Start

### 1. Store your API keys (encrypted)
```powershell
. .\env-manager.ps1
env-set ANTHROPIC_API_KEY sk-ant-...
env-set GEMINI_API_KEY AIza...
env-set GROK_API_KEY xai-...
env-set GITHUB_TOKEN ghp_...
```

### 2. Generate your cheatsheet
```powershell
.\gen-cheatsheet.ps1
```

### 3. Launch the REPL
```powershell
.\repl.ps1
```

---

## env-manager.ps1

Encrypts secrets using **Windows DPAPI** — bound to your user account. No password needed, no plaintext files.

| Command | Description |
|---|---|
| `env-set KEY VALUE` | Add or update a secret |
| `env-get KEY` | Decrypt and display one secret |
| `env-load` | Load all secrets into current session |
| `env-list` | Show all key names (no values) |
| `env-delete KEY` | Remove a secret |
| `env-edit` | Interactive menu |
| `env-export-temp` | Plaintext export, auto-deletes in 60s |

> **Note:** `.env.encrypted` can only be decrypted by the same Windows user on the same machine. If you move machines, re-run `env-set` for each key.

---

## gen-cheatsheet.ps1

An AI-agentic script that reads your PowerShell profile and config files, strips anything matching `.cheatsheet-ignore`, and sends the sanitized code to Claude to generate `CHEATSHEET.md`.

```powershell
.\gen-cheatsheet.ps1                  # full regeneration
.\gen-cheatsheet.ps1 -Section git     # regenerate one section only
.\gen-cheatsheet.ps1 -Dry             # preview what gets sent (no API call)
.\gen-cheatsheet.ps1 -Query "aws"     # search existing cheatsheet
```

---

## repl.ps1

An interactive shell with meta-commands (`:command`) on top of normal PowerShell execution.

```powershell
.\repl.ps1           # full banner
.\repl.ps1 -Minimal  # quiet mode
```

### Key REPL commands

| Command | Description |
|---|---|
| `:help` | Show all commands |
| `:ask <prompt>` | Ask Claude |
| `:gem <prompt>` | Ask Gemini |
| `:grok <prompt>` | Ask Grok |
| `:explain <cmd>` | Ask Claude to explain a shell command |
| `:fix` | Ask Claude to fix your last error |
| `:cs` | View full cheatsheet |
| `:cs <term>` | Search cheatsheet |
| `:regen` | Regenerate cheatsheet via AI |
| `:ctx` | Show current cloud/AI context |
| `:env list/set/get/load` | Manage secrets inline |
| `:aws <profile>` | Switch AWS profile |
| `:gcp <project>` | Switch GCP project |
| `:history` | Command history |
| `:quit` | Exit |

---

## .gitignore recommendation

Add to your `.gitignore` if this project is version controlled:

```
.env
.env.*
.env.encrypted
secrets.ps1
*.key
*.pem
CHEATSHEET.md   # optional — re-gen is fast
```
