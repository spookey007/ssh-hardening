# SSH Hardening

Lock down SSH on **Debian/Ubuntu** in one run: new port, no root login, key-based auth, optional UFW and Fail2Ban.

---

## Quick start (step-by-step)

### 1️⃣ Install git (if needed)

On Debian/Ubuntu:

```bash
sudo apt-get install -y git
```

### 2️⃣ Clone the repo and enter the folder

```bash
git clone https://github.com/spookey007/ssh-hardening.git
cd ssh-hardening
```

### 3️⃣ Make the scripts executable

```bash
chmod +x ssh_harden.sh script.sh
```

If you skip this, you may get **"command not found"** when running `./ssh_harden.sh`. If that happens, use step 5 with `sudo bash ssh_harden.sh` instead.

### 4️⃣ Create an SSH key on your PC (to paste as `SSH_PUB_KEY`)

**Linux / macOS**

```bash
ssh-keygen -t ed25519 -C "your_email@example.com"
```

Press Enter for default path (`~/.ssh/id_ed25519`). Optional: set a passphrase.

Show your **public** key (copy this into `SSH_PUB_KEY`):

```bash
cat ~/.ssh/id_ed25519.pub
```

**Windows (PowerShell or Git Bash)**

```powershell
ssh-keygen -t ed25519 -C "your_email@example.com"
```

Press Enter for default path. Optional: set a passphrase.

Show your **public** key:

- **PowerShell:** `Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub`
- **CMD:** `type %USERPROFILE%\.ssh\id_ed25519.pub`

Copy the whole line (starts with `ssh-ed25519 ...`). That is your `SSH_PUB_KEY`.

### 5️⃣ Run the script as root

Replace the values with yours, then run:

```bash
sudo SSH_USER=kamaileo \
     SSH_PASS='YourStrongPassword123!' \
     SSH_PORT=49221 \
     PORTS="5060,5061,10000-20000" \
     SSH_PUB_KEY="ssh-ed25519 AAAA... fahad@yourmachine" \
     ./ssh_harden.sh
```

If you get **"command not found"**, use:

```bash
sudo bash ssh_harden.sh
```

(with the same `SSH_USER=... SSH_PASS=...` etc. in front).

### 6️⃣ Follow the prompts

- Confirm the settings (user, port, key).
- Choose **Y** or **n** for UFW and Fail2Ban.

### 7️⃣ Test login (before closing your current session)

In a **new** terminal:

```bash
ssh -p 49221 kamaileo@YOUR_SERVER_IP
```

Use the **port** and **user** you set. Only close the original session after you confirm login and `sudo` work.

---

## If the user already exists

If `SSH_USER` is already on the server, the script **does not** create a new user and **does not** change the password. It only:

- Ensures the user is in the `sudo` group
- Updates `~/.ssh/authorized_keys` if you pass `SSH_PUB_KEY`
- Hardens SSH config, and optionally UFW and Fail2Ban

So you can run it again to “harden only” without touching the existing password.

---

## What you need to set

| Variable | Example | What it does |
|----------|---------|--------------|
| `SSH_USER` | `kamaileo` | Username (created if missing; if it exists, password is left unchanged). |
| `SSH_PASS` | `'YourPass123!'` | Password for **new** users only. Use a strong one. |
| `SSH_PORT` | `49221` | SSH port. You’ll use: `ssh -p 49221 user@server`. |
| `PORTS` | `"5060,5061,10000-20000"` | Extra ports for UFW (optional). |
| `SSH_PUB_KEY` | `"ssh-ed25519 AAAA..."` | Your **public** key. Strongly recommended so you don’t get locked out. |

---

## OS support & git install

| OS | Supported | Tested | Git install |
|----|-----------|--------|-------------|
| **Debian 12 x64** | ✅ | ✅ | `sudo apt-get install -y git` |
| Debian 11/10, Ubuntu 24/22/20 | ✅ | ❌ | `sudo apt-get install -y git` |
| RHEL / Rocky / Alma / CentOS | ❌ | ❌ | `sudo yum install -y git` |
| Fedora | ❌ | ❌ | `sudo dnf install -y git` |
| Arch | ❌ | ❌ | `sudo pacman -Syu git` |
| openSUSE | ❌ | ❌ | `sudo zypper install -y git` |

On unsupported OSes the script prints **Coming soon 😊** and exits without changing anything.

---

## Security notes

- Set **`SSH_PUB_KEY`** so you can still log in after password auth is disabled.
- Test on a **VM or disposable server** first.
- Keep your current session open until you’ve tested `ssh -p PORT user@server`.

---

## Author

[@spookey007](https://github.com/spookey007)
