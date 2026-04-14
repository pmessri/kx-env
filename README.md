# kx-env

A cross-platform developer environment designed for consistency across Windows and Linux/WSL.
Built to eliminate context-switching friction between environments by providing a unified
shell experience with shared tooling, secret management, and environment configuration
under a single codebase.

## Project Structure
kx-env/
├── README.md
├── .gitignore
├── starship.toml              # shared Starship prompt configuration
│
├── kx.ps/                     # PowerShell environment (Windows)
│   ├── Microsoft.PowerShell_profile.ps1
│   ├── env-manager.ps1        # load/unload encrypted environment variables
│   ├── gen-cheatsheet.ps1     # auto-generate CHEATSHEET.md from scripts
│   ├── repl.ps1               # interactive REPL utilities
│   └── bootstrap.ps1          # one-command setup on a fresh machine
│
└── kx.bs/                     # Bash environment (Linux / WSL / Cloud)
├── .bashrc
├── env-manager.sh
├── gen-cheatsheet.sh
├── repl.sh
└── bootstrap.sh

---

## Features

- **Unified environment** across PowerShell and Bash
- **Secret management** via encrypted `.env` files - API keys never committed
- **Cheatsheet generation** - auto-generated `CHEATSHEET.md` per shell
- **Starship prompt** - shared config for a consistent terminal experience
- **Bootstrap scripts** - one-command setup on a fresh machine

---

## Getting started

### Prerequisites

| Tool | Windows | Linux / WSL |
| ---- | ------- | ----------- |
| PowerShell 7+ | Required | - |
| Bash 5+       | Required |
| Starship | `winget install Starship.Starship` | `curl -sS
https://starship.rs/install.sh \| sh` |
| Git | `winget install Git.Git` | `apt install git` |

### Windows (PowerShell)

```powershell
git clone https://github.com/pmessri/kx-env.git
cd kx-env\kx.ps
.\bootstrap.ps1

### Linux / WSL / Cloud (Bash)

```bash
git clone https://github.com/pmessri/kx-env.git
cd kx-env/kx.bs
chmod +x bootstrap.sh
./bootstrap.sh
```

---

### Security
Secret management is enforced at the repo level. The following are excluded from version
control via `.gitignore` and should never be committed:

| File pattern | Reason |
| ------------ | ------ |
| `.env`, `.env.*` | Environment variables and API keys |
| `*.encrypted` | Encrypted secret stores |
| `secrets.ps1`, `secrets.sh` | Shell-specific secret loaders |
| `CHEATSHEET.md` | Auto-generated, may contain sensitive path info |
| `*.key`, `*.pem`, `*.pfx` | Certificates and private keys |

Secrets are managed locally through `env-manager` scripts which handle encryption,
loading, and unloading without ever writing plaintext values to disk in a tracked
location.

---

## Author

**pmessri** . [github.com/pmessri] (https://github.com/pmessri)

