# SSH Hardening

One-command SSH lockdown for **Debian** and **Ubuntu**. Stop leaving your server on the default setup that every bot on the internet is built to exploit.

---

## Your server is a target right now

**Every server with SSH on port 22 and root login enabled gets hit.** Automated scanners probe thousands of IPs per minute. Weak or default SSH config is how most breaches start: one guessed or leaked password, and someone else owns your box.

**If you don’t harden SSH:**

| You leave it as-is | What actually happens |
|--------------------|------------------------|
| SSH on port **22** | Bots hammer your login 24/7. One weak password and you’re compromised. |
| **Root login** allowed | Attacker gets full control in one step. No separate user, no audit trail. |
| **Password-only** auth | Brute-force and credential stuffing work. Keys don’t get “guessed.” |
| **No firewall** | Every open port is discoverable and attackable. No default-deny. |
| **No Fail2Ban** | Unlimited login attempts. No temporary bans, no rate limiting. |

**Real consequences:** Unauthorized access, cryptominers, backdoors, data theft, or your server turned into a relay for attacks. Fixing it after a breach is always harder and more expensive than locking the door now.

---

## What you get when you use this script

- **No more root over SSH** — Dedicated user + sudo. One less way to own the whole system.
- **SSH off port 22** — Moves to a port you choose (or random). Cuts a lot of automated noise and targeted brute-force.
- **Key-based auth** — Use `SSH_PUB_KEY`; script can disable password logins so keys are the only way in.
- **Optional UFW** — Default-deny incoming, allow only SSH (your port) and any extra ports you need.
- **Optional Fail2Ban** — Bans IPs after failed SSH attempts. Slows down and deters brute-force.

**Truth:** This script applies common, sensible hardening in one run. It does **not** replace regular updates, strong keys, or good access control—but it closes the biggest SSH holes fast.

---

## How to run it (step-by-step)

**1. Clone the repo and go into the folder**

```bash
git clone https://github.com/spookey007/ssh-hardening.git
cd ssh-hardening
```

**2. Run the script as root with your settings**

You **must** use `sudo`. Set at least:

- `SSH_USER` — name of the admin user to create (e.g. `myadmin`)
- `SSH_PASS` — that user’s password (use a strong one)
- `SSH_PORT` — port for SSH (e.g. `49221`). **Remember this port**—you’ll use it to connect later.
- `SSH_PUB_KEY` — your SSH **public** key (strongly recommended so you don’t get locked out).

Optional:

- `PORTS` — extra ports/ranges for UFW, comma-separated (e.g. `5060,5061,10000-20000`). Only used if you say “yes” to UFW.

**Example (replace the values with yours):**

```bash
sudo SSH_USER=myadmin \
     SSH_PASS='YourStrongPassword123!' \
     SSH_PORT=49221 \
     PORTS="5060,5061,10000-20000" \
     SSH_PUB_KEY="ssh-rsa AAAAB3NzaC1yc2E... your-key-comment" \
     ./ssh_harden.sh
```

**3. Follow the prompts**

- The script shows detected OS (Debian/Ubuntu), user, port, and whether a key is set. Confirm to continue.
- It asks: **Configure UFW firewall?** — Say yes unless you already manage a firewall.
- It asks: **Install and configure Fail2Ban?** — Say yes for brute-force protection.

**4. After it finishes**

In a **new** terminal (keep your current session open), test login:

```bash
ssh -p 49221 myadmin@YOUR_SERVER_IP
```

Use the **port** and **user** you set. Only close your original session once you’ve confirmed you can log in and use `sudo`.

---

## What the script actually does (truthful)

### Every run

- **User:** Creates `SSH_USER` if it doesn’t exist (or updates password and sudo if it does). Adds the user to the `sudo` group.
- **SSH directory:** Creates `~/.ssh` for that user with mode `700`. If you passed `SSH_PUB_KEY`, it writes `authorized_keys` with mode `600`.
- **sshd_config:** Backs up `/etc/ssh/sshd_config` to a timestamped file, then sets:
  - `Port` → your chosen port  
  - `PermitRootLogin no`  
  - `PasswordAuthentication` → `no` if you have a key (or if you confirm when asked); otherwise leaves it `yes` so you don’t lock yourself out  
  - `PubkeyAuthentication yes`  
  - `ChallengeResponseAuthentication no`  
  - `UsePAM yes`  
- Runs `sshd -t` to check config, then restarts `ssh` or `sshd`.

### If you choose “Configure UFW”

- Installs UFW if missing (skips if already installed).
- Sets default deny incoming, allow outgoing.
- Allows your SSH port and any ports/ranges in `PORTS`.
- Enables UFW.

### If you choose “Install and configure Fail2Ban”

- Installs Fail2Ban if missing (skips if already installed).
- Enables and starts the service.
- Adds a jail in `/etc/fail2ban/jail.d/ssh-hardening.conf` for your SSH port (maxretry 5, bantime 3600).
- Restarts Fail2Ban.

### Optional

- **Debian:** runs `./debian/ssh_harden_extra.sh` if that file exists and is executable.
- **Ubuntu:** runs `./ubuntu/ssh_harden_extra.sh` if that file exists and is executable.

---

## Requirements

- **OS:** Debian or Ubuntu (or something that sets `ID`/`ID_LIKE` in `/etc/os-release`).
- **Privilege:** Root (e.g. `sudo`).
- **Network:** Outbound HTTPS for `apt` if the script installs UFW or Fail2Ban.

---

## Environment variables (reference)

| Variable | Required | Default | What it does |
|----------|----------|---------|--------------|
| `SSH_USER` | No | `adminuser` | Username to create (or update) for SSH and sudo. |
| `SSH_PASS` | No | `ChangeMe123!` | That user’s password. **Always set a strong one.** |
| `SSH_PORT` | No | Random 10000–65535 | Port for SSH. You’ll use this in `ssh -p PORT ...`. |
| `PORTS` | No | *(none)* | Comma-separated ports or ranges for UFW (e.g. `5060,10000-20000`). Used only if you enable UFW. |
| `SSH_PUB_KEY` | **Strongly recommended** | *(none)* | Your SSH public key. Prevents lockout when password auth is disabled. |

---

## Important security notes

1. **Avoid lockout** — Set `SSH_PUB_KEY` before disabling password auth, or ensure you have console access (e.g. provider’s VNC) and test in a new session before closing the old one.
2. **Test first** — Prefer a test VM or disposable server before running on production.
3. **Secrets** — `SSH_PASS` and `SSH_PUB_KEY` can show up in process lists and shell history. Use a protected env file or clear history if that’s a concern.
4. **No warranty** — You are responsible for your systems. Review the script and understand the changes before running.

---

## Repo layout

```
ssh-hardening/
├── README.md
├── ssh_harden.sh   # Entry point — run this
├── script.sh       # Main logic
├── debian/         # Optional: ssh_harden_extra.sh
└── ubuntu/         # Optional: ssh_harden_extra.sh
```

---

## License

Use and modify as you like. No warranty; you are responsible for your systems and data.

---

## Author

- **GitHub:** [@spookey007](https://github.com/spookey007)
