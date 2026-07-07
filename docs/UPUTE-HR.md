# WisperLocal — Upute za korištenje

**WisperLocal** je mala aplikacija za Mac koja pretvara govor u tekst: pritisneš tipku, govoriš, i tekst se sam upiše u aplikaciju u kojoj se nalaziš (Slack, Mail, browser, Word…). Radi **100% offline** — ništa se ne šalje na internet, sve ostaje na tvom Macu. Glavni jezik je **hrvatski** (radi i engleski) i prepoznavanje je jako dobro. Aplikacija stoji u gornjoj traci (ikonica 🎤), bez ikone u docku.

## Što ti treba
- **Mac s Apple Silicon čipom (M1 ili noviji)**
- **macOS 13** ili noviji

## Instalacija — obavezno u Terminalu
Otvori **Terminal** (Cmd + Space → utipkaj „Terminal" → Enter), zalijepi ovu jednu liniju i pritisni Enter:

```bash
curl -fL https://raw.githubusercontent.com/makeit-web/WisperLocal/main/scripts/install-prebuilt.sh -o /tmp/wl-install.sh && bash /tmp/wl-install.sh
```

> ⚠️ Mora se pokrenuti **u Terminalu**. Ako samo otvoriš ili dupli-klikneš datoteku, vidjet ćeš kod i **ništa se neće instalirati**.

Instalacija skine aplikaciju i hrvatski model (~834 MB, jednom).

## Prvi put (jednom po računalu)
1. Pokreni aplikaciju (**Launchpad → WisperLocal**).
2. Dozvoli **Mikrofon** kad pita.
3. Dozvoli **Accessibility**: klikni **🎤** u gornjoj traci → **„Open Accessibility Settings…"** → uključi **WisperLocal** → **ugasi i ponovo pokreni aplikaciju**. (Bez ovog koraka app neće moći tipkati.)

## Korištenje
Dvaput brzo pritisni **Ctrl** → izgovori tekst → opet dvaput **Ctrl**. Tekst se upiše sam, tamo gdje ti je kursor.

## Ako vidiš katanac 🔐
Znači Accessibility još nije uključen. Tvoj tekst je ipak spremljen — pritisni **Cmd + V** da ga zalijepiš, pa ponovi korak 3 gore.

## Neobavezno: pokretanje pri paljenju Maca
U **🎤** meniju uključi **„Launch at Login"** i app će se sam dizati kad se prijaviš.

## Privatnost
Sve se odvija lokalno na tvom Macu. Zvuk, tekst i sve ostalo **nikad ne napuštaju računalo** — nema interneta, nema slanja, nema praćenja.
