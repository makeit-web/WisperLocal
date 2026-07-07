# WisperLocal — User Guide

**WisperLocal** is a small Mac app that turns speech into text: press a key, speak, and the text is typed straight into whatever app you're in (Slack, Mail, browser, Word…). It works **100% offline** — nothing is sent to the internet, everything stays on your Mac. The primary language is **Croatian** (English works too) and recognition is very good. The app lives in the menu bar (🎤 icon), with no dock icon.

## Requirements
- **Mac with Apple Silicon (M1 or newer)**
- **macOS 13** or newer

## Install — must be run in Terminal
Open **Terminal** (Cmd + Space → type "Terminal" → Enter), paste this single line and press Enter:

```bash
curl -fL https://raw.githubusercontent.com/makeit-web/WisperLocal/main/scripts/install-prebuilt.sh -o /tmp/wl-install.sh && bash /tmp/wl-install.sh
```

> ⚠️ It must run **in Terminal**. If you just open or double-click the file, you'll see code and **nothing will be installed**.

The install downloads the app and the Croatian model (~834 MB, one time).

## First run (once per machine)
1. Launch the app (**Launchpad → WisperLocal**).
2. Allow **Microphone** when asked.
3. Grant **Accessibility**: click **🎤** in the menu bar → **"Open Accessibility Settings…"** → enable **WisperLocal** → **quit and relaunch the app**. (Without this step the app can't type.)

## Usage
Double-tap **Ctrl** → speak → double-tap **Ctrl** again. The text is typed automatically wherever your cursor is.

## If you see a padlock 🔐
Accessibility isn't enabled yet. Your text is still saved — press **Cmd + V** to paste it, then repeat step 3 above.

## Optional: launch at login
In the **🎤** menu, enable **"Launch at Login"** and the app will start automatically when you log in.

## Privacy
Everything happens locally on your Mac. Audio, text, and everything else **never leave the computer** — no internet, no uploads, no tracking.
