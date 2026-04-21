# OpenClaw Mobile Port

Run [OpenClaw](https://openclaw.ai) on your Android phone via Termux, while all heavy `bash`/`exec` work is forwarded to a remote SSH compute host that **you** provide.

> **Phone** = OpenClaw gateway + Telegram bot (lightweight)
> **SSH server** = Where commands actually execute (your VPS / box / Replit / anywhere with SSH)

---

## العربية — تثبيت سريع

أنت بحاجة إلى:

1. هاتف أندرويد + تطبيق [Termux](https://f-droid.org/packages/com.termux/) (من F-Droid وليس متجر Play).
2. خادم SSH خاص بك (VPS، أو Replit Workspace، أو أي جهاز عليه `sshd`).
3. توكن بوت تيليجرام (اختياري إذا كنت ستستخدم تيليجرام).

افتح Termux ونفّذ:

```bash
curl -fsSL https://raw.githubusercontent.com/hakercryptoplus-svg/openclaw-mobile/main/install-termux.sh | bash
```

سيسألك السكربت عن:

- عنوان خادم SSH بصيغة `user@host:port` (مثال: `ahmad@vps.example.com:22`).
- محتوى مفتاح SSH الخاص (يُلصق مرة واحدة ويُحفظ كسرّ، لا يُكتب في أي ملف إعدادات).
- (اختياري) توكن بوت تيليجرام و chat ID.

ثم يقوم بـ:

- تثبيت Node.js و OpenSSH و Git داخل Termux.
- استنساخ OpenClaw وبناءه.
- توليد ملف `~/.openclaw/openclaw.json` يُوجّه كل تنفيذ إلى خادمك عبر SSH.
- توفير الأمر `openclaw-mobile` لتشغيل/إيقاف/تحديث الخدمة.

التشغيل اليومي:

```bash
openclaw-mobile start    # تشغيل
openclaw-mobile logs     # متابعة السجلات
openclaw-mobile stop     # إيقاف
openclaw-mobile update   # تحديث
openclaw-mobile config   # تعديل الإعدادات
```

---

## English — Quick Install

You need:

1. An Android phone with [Termux](https://f-droid.org/packages/com.termux/) installed from F-Droid (NOT Play Store).
2. Your own SSH server (any VPS, a Replit workspace, or any box running `sshd`).
3. (Optional) A Telegram bot token if you want a Telegram channel.

In Termux, run:

```bash
curl -fsSL https://raw.githubusercontent.com/hakercryptoplus-svg/openclaw-mobile/main/install-termux.sh | bash
```

The installer will:

- Install Node.js, OpenSSH, Git inside Termux.
- Prompt you for your SSH target (`user@host:port`), your SSH private key, and optional Telegram credentials.
- Store the SSH key as a Termux env secret (mode `600`), never written into any config file.
- Install OpenClaw from npm (`npm install -g openclaw`).
- Write `~/.openclaw/openclaw.json` configured to forward all `bash`/`exec` to your SSH host via OpenClaw's built-in `sandbox.backend = "ssh"`.
- Install the `openclaw-mobile` launcher into `$PREFIX/bin`.

Daily use:

```bash
openclaw-mobile start    # start the gateway
openclaw-mobile logs     # tail logs
openclaw-mobile stop     # stop
openclaw-mobile update   # pull updates
openclaw-mobile config   # edit settings
```

---

## How It Works

OpenClaw natively supports an SSH execution backend (`src/agents/sandbox/ssh.ts`). This port simply ships:

1. A Termux-aware installer that handles `pkg`-based dependencies and Node.js setup on Android.
2. An interactive config generator that:
   - Sets `agents.defaults.sandbox.backend = "ssh"`.
   - Stores your SSH credentials as Termux environment secrets (`OPENCLAW_SSH_*`).
   - Writes a config that references those secrets via `${VAR}` template syntax, so the actual key never sits in `openclaw.json`.
3. A `openclaw-mobile` wrapper that manages a long-running OpenClaw gateway via `nohup` + a PID file (`start`/`stop`/`restart`/`logs`/`status`), optimized for Termux background limits (works best with `termux-wake-lock`).

Every prompt OpenClaw runs — every shell command, every file read/write — is transparently forwarded to your SSH host. Your phone only handles the bot/gateway logic and stays cool.

---

## Security

- **Your SSH private key never leaves Termux.** It is stored as an environment variable in `~/.openclaw-mobile/env` (mode `600`) and referenced from the config via `${OPENCLAW_SSH_PRIVATE_KEY}` syntax.
- **Telegram tokens** are stored the same way.
- Use a **dedicated SSH key** for OpenClaw (don't reuse your personal key). The installer will offer to generate one for you.
- Restrict the key on the server side via `~/.ssh/authorized_keys` options like `command=`, `from=`, etc., if you want to limit what OpenClaw can do.

---

## License

MIT — see [LICENSE](./LICENSE).

OpenClaw itself is licensed separately at [openclaw.ai](https://openclaw.ai).
