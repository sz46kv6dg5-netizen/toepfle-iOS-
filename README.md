# Töpfle 🍲 – iOS Rezept-App & FastAPI Backend

**Töpfle** ist eine native iOS-Rezept-App mit Share Extension, KI-gestütztem FastAPI-Backend (ReciMe-Kaskadenlogik) und automatisierter TestFlight CI/CD Pipeline via GitHub Actions.

---

## 📱 Projekt-Übersicht

- **Haupt-App:** Native SwiftUI App mit SwiftData (`de.toepfle.app`)
- **Share Extension:** Schnellspeichern aus TikTok, Facebook & Co. (`de.toepfle.app.share`)
- **App Group:** `group.de.toepfle.app` (Gemeinsame Warteschlange & Einstellungen)
- **Backend:** FastAPI auf Ubuntu VPS mit `google-genai` und `yt-dlp`
- **Produktions-URL:** `https://rezepte.icareberlin.de/api`

---

## 🚀 1. Backend-Deployment (IONOS VPS / Ubuntu)

### Voraussetzungen
- Ubuntu 22.04 oder 24.04 LTS
- Python 3.10+ & `python3-venv`
- Node.js & PM2 (`npm install -g pm2`)
- Nginx & Certbot

### Installation & Start
```bash
# 1. Repository klonen / ins Backend-Verzeichnis wechseln
cd /var/www/toepfle/backend

# 2. Python Virtual Environment einrichten
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

# 3. Umgebungsvariablen anlegen
cp .env.example .env
nano .env
# Trage dort GEMINI_API_KEY und APP_API_KEY ein!

# 4. Dienst mit PM2 starten
pm2 start ecosystem.config.js
pm2 save
pm2 startup
```

### Nginx-Einbindung
```bash
# Nginx Konfiguration kopieren
sudo cp nginx-rezepte.conf /etc/nginx/sites-available/rezepte.icareberlin.de
sudo ln -s /etc/nginx/sites-available/rezepte.icareberlin.de /etc/nginx/sites-enabled/

# Testen und neu laden
sudo nginx -t
sudo systemctl reload nginx

# SSL-Zertifikat mit Let's Encrypt einrichten
sudo certbot --nginx -d rezepte.icareberlin.de
```

---

## 🛠 2. iOS-App lokal bauen (macOS & Xcode)

Das Projekt nutzt **XcodeGen**, um das `.xcodeproj` dynamisch und konfliktfrei zu generieren.

```bash
# 1. XcodeGen installieren
brew install xcodegen

# 2. In den iOS-Ordner wechseln und Xcode-Projekt erzeugen
cd ios
xcodegen generate

# 3. Projekt in Xcode öffnen
open Toepfle.xcodeproj
```

---

## 🔐 3. GitHub Secrets für TestFlight CI/CD

Für den automatischen TestFlight-Build und -Upload über `.github/workflows/ios-testflight.yml` müssen folgende Secrets im GitHub-Repository hinterlegt werden:

| Secret Name | Beschreibung |
| :--- | :--- |
| `BUILD_CERTIFICATE_BASE64` | Base64-kodiertes iOS Distribution Zertifikat (`.p12`) |
| `P12_PASSWORD` | Passwort des `.p12` Zertifikats |
| `KEYCHAIN_PASSWORD` | Beliebiges temporäres Passwort für die CI-Keychain |
| `APP_PROVISIONING_PROFILE_BASE64` | Base64-kodiertes Provisioning Profile der Haupt-App (`de.toepfle.app`) |
| `SHARE_PROVISIONING_PROFILE_BASE64` | Base64-kodiertes Provisioning Profile der Share Extension (`de.toepfle.app.share`) |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID des App Store Connect API-Keys (z. B. `2X9R4HX4P3`) |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID von App Store Connect (UUID) |
| `APP_STORE_CONNECT_API_KEY_BASE64` | Base64-Inhalt des privaten Schlüssels (`AuthKey_XXXXX.p8`) |

### Base64 Encoding Befehl (macOS/Linux)
```bash
base64 -i dateiname.mobileprovision | pbcopy   # macOS
base64 -w 0 dateiname.mobileprovision           # Linux
```

---

## 🧠 4. ReciMe-Kaskadenlogik im Backend

1. **Stufe 1 (0 MB Download, < 2s):**
   - Ruft via `yt-dlp` Metadaten und die Beschreibung (Caption) ab.
   - Hat die Caption mindestens 120 Zeichen, prüft Gemini 2.5 Flash, ob bereits Zutaten und Schritte vorhanden sind.
   - Falls ja, wird das fertige Rezept sofort ohne Videodownload zurückgeliefert.

2. **Stufe 2 (Multimodaler Fallback):**
   - Falls die Beschreibung kein vollständiges Rezept enthält, lädt das Backend das Video temporär nach `/tmp/` herunter.
   - Das Video wird zu Gemini File API hochgeladen und audiovisuell analysiert.
   - Sowohl die Gemini-Remote-Datei als auch die lokale Datei in `/tmp/` werden im `finally`-Block garantiert gelöscht.
