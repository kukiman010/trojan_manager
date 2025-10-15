[![License: MIT][mit-shield]][mit]

[mit]: https://opensource.org/licenses/MIT
[mit-shield]: https://img.shields.io/badge/License-MIT-yellow.svg


`trojan_manager` is a handy Bash utility for managing users of the [Trojan VPN protocol](https://github.com/trojan-gfw/trojan). It helps admins quickly add/delete users, generate ready-to-use VPN config strings and QR codes, and perform basic access management on small and medium servers.

### Features

- Add new users for Trojan VPN
- Generate connection URI and QR code (for fast onboarding)
- Manage users: remove, lock by date, regenerate password
- Logs all actions
- Integrates with systemd trojan service
- MIT licensed


### Requirements

> Note:  
> Place trojan_manager.sh into your Trojan installation directory, typically `/usr/local/etc/trojan/`.

- Bash (tested on Linux)
- jq (`sudo apt install jq`)
- qrencode (`sudo apt install qrencode`)
- systemd, trojan running as a servicegit 

### Quick Start

1. Copy `trojan_manager.sh` to a folder and make it executable:  
   ```bash
   chmod +x trojan_manager.sh
   ```
2. Ensure dependencies are installed:
   ```bash
   sudo apt install jq qrencode
   ```
3. Run with root privileges, for example, to add a user:
   ```bash
   sudo ./trojan_manager.sh --new username
   ```
   The script will display a connection URI and a QR code for the new user.

### Main Commands

- `--new <user>` — create a new user with a unique password
- `--list` — list and manage users (regenerate password, lock, delete, show QR, etc)
- `--qr <user>` — show a QR code for specified user
- `--config <user>` — print user's connection URI
- `--restart` — restart `trojan.service`
- `--help` — print help

### Config files

- The script expects a `config.json` file with a password array, each entry in form `"username_password"`
- User metadata is kept in `users.json`



