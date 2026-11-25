import glob
import json
import logging
import os
import re
import time
import uuid
from typing import List, Literal, Optional

from fastapi import Depends, FastAPI, HTTPException, Security, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import APIKeyHeader
from google import genai
from google.genai import types
from pydantic import BaseModel, Field
from pydantic_settings import BaseSettings, SettingsConfigDict
import yt_dlp

# --- Logging Configuration ---
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("toepfle-backend")

# --- Environment & Configuration ---
class Settings(BaseSettings):
    GEMINI_API_KEY: str = ""
    APP_API_KEY: str = ""
    PORT: int = 8015

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

settings = Settings()

# --- Schemas ---
CategoryType = Literal["Hauptgericht", "Dessert", "Frühstück", "Snack", "Backen"]

class IngredientItem(BaseModel):
    amount: Optional[float] = Field(
        default=None,
        description="Numerischer Mengenangabe (z. B. 250 oder 1.5). None falls unbestimmt (z. B. 'etwas Salz').",
    )
    unit: str = Field(
        default="",
        description="Maßeinheit wie 'g', 'ml', 'EL', 'TL', 'Prise', 'Stück' oder leer.",
    )
    name: str = Field(
        ...,
        description="Name der Zutat (z. B. 'Mehl', 'Milch', 'Knoblauchzehen').",
    )

class ExtractRecipeRequest(BaseModel):
    url: str = Field(..., description="Die URL des Social-Media-Posts (TikTok, Facebook, YouTube, etc.)")

class RecipeResponse(BaseModel):
    title: str
    prep_time: str
    servings: int = 4
    category: str
    ingredients: List[IngredientItem]
    instructions: List[str]
    original_url: str
    source_platform: str
    thumbnail_url: Optional[str] = None

class FastMetadataRecipeCheck(BaseModel):
    has_complete_recipe: bool
    title: Optional[str] = None
    prep_time: Optional[str] = None
    servings: Optional[int] = 4
    category: Optional[str] = "Hauptgericht"
    ingredients: Optional[List[IngredientItem]] = []
    instructions: Optional[List[str]] = []

class MultimodalRecipeExtraction(BaseModel):
    title: str
    prep_time: str
    servings: int = 4
    category: str
    ingredients: List[IngredientItem]
    instructions: List[str]

# --- FastAPI Initialization ---
app = FastAPI(
    title="Töpfle Recipe Extraction API",
    version="1.0.0",
    description="Backend für die Töpfle iOS App zur KI-gestützten Rezeptextraktion aus Social Media Videos.",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Authentication Dependency ---
API_KEY_HEADER = APIKeyHeader(name="X-API-Key", auto_error=False)

async def verify_api_key(api_key: Optional[str] = Security(API_KEY_HEADER)) -> str:
    expected_key = settings.APP_API_KEY.strip()
    if not expected_key:
        logger.warning("APP_API_KEY ist in der Server-Konfiguration nicht gesetzt!")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server-Konfigurationsfehler: APP_API_KEY nicht hinterlegt.",
        )
    if not api_key or api_key.strip() != expected_key:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Ungültiger oder fehlender API-Key im X-API-Key Header.",
        )
    return api_key

# --- Helper Functions ---
def detect_platform(url: str) -> str:
    low = url.lower()
    if "tiktok.com" in low:
        return "tiktok"
    elif "facebook.com" in low or "fb.watch" in low:
        return "facebook"
    elif "youtube.com" in low or "youtu.be" in low:
        return "youtube"
    return "web"

def sanitize_category(cat: Optional[str]) -> str:
    valid_categories = {"Hauptgericht", "Dessert", "Frühstück", "Snack", "Backen"}
    if cat and cat in valid_categories:
        return cat
    if not cat:
        return "Hauptgericht"
    c_lower = cat.lower()
    if "dessert" in c_lower or "nachtisch" in c_lower or "süß" in c_lower:
        return "Dessert"
    if "frühstück" in c_lower or "breakfast" in c_lower:
        return "Frühstück"
    if "snack" in c_lower or "vorspeise" in c_lower:
        return "Snack"
    if "backen" in c_lower or "kuchen" in c_lower or "brot" in c_lower or "gebäck" in c_lower:
        return "Backen"
    return "Hauptgericht"

def get_gemini_client() -> genai.Client:
    api_key = settings.GEMINI_API_KEY.strip()
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="GEMINI_API_KEY ist auf dem Server nicht konfiguriert.",
        )
    return genai.Client(api_key=api_key)

# --- Endpoints ---
@app.get("/health")
async def health_check():
    """Öffentlicher Healthcheck für Monitoring und Nginx."""
    return {
        "status": "ok",
        "app": "Töpfle API",
        "gemini_configured": bool(settings.GEMINI_API_KEY.strip()),
        "auth_configured": bool(settings.APP_API_KEY.strip()),
    }

@app.post("/extract-recipe", response_model=RecipeResponse, dependencies=[Depends(verify_api_key)])
async def extract_recipe(payload: ExtractRecipeRequest):
    """
    ReciMe-Kaskadenlogik:
    1. Metadaten- & Caption-Check (0 MB Video-Download)
    2. Fallback: Temporärer Video-Download & Multimodale KI-Analyse mit automatischer Bereinigung
    """
    raw_url = payload.url.strip()
    if not raw_url:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="URL darf nicht leer sein.")

    logger.info(f"Beginne Rezeptextraktion für URL: {raw_url}")
    gemini_client = get_gemini_client()

    # --- Stufe 1: Schneller Metadaten- & Caption-Check ---
    ydl_metadata_opts = {
        "quiet": True,
        "skip_download": True,
        "no_warnings": True,
        "extract_flat": False,
    }

    metadata = {}
    try:
        with yt_dlp.YoutubeDL(ydl_metadata_opts) as ydl:
            metadata = ydl.extract_info(raw_url, download=False) or {}
    except Exception as e:
        logger.warning(f"Metadaten-Extraktion via yt-dlp fehlgeschlagen oder unvollständig: {e}")

    resolved_url = metadata.get("webpage_url") or raw_url
    meta_title = metadata.get("title") or ""
    meta_description = metadata.get("description") or ""
    meta_thumbnail = metadata.get("thumbnail")
    platform = detect_platform(resolved_url)

    logger.info(
        f"Metadaten erhalten: resolved_url={resolved_url}, Plattform={platform}, "
        f"Titel='{meta_title}', Beschreibungslänge={len(meta_description)}"
    )

    # Prüfen, ob Caption lang genug ist für vollständiges Rezept (mindestens 120 Zeichen)
    if len(meta_description) >= 120:
        logger.info("Stufe 1 aktiv: Analysiere Titel & Caption mit Gemini...")
        stage1_prompt = f"""Du bist ein kulinarischer Experte für die Rezept-App 'Töpfle'.
Analysiere die folgenden Metadaten eines Koch-Videos (Titel und Beschreibung/Caption).

Titel: {meta_title}
Beschreibung/Caption:
{meta_description}

Deine Aufgabe:
1. Prüfe sorgfältig, ob in der Beschreibung bereits ein VOLLSTÄNDIGES Koch- oder Backrezept enthalten ist.
   Ein vollständiges Rezept besitzt:
   - Eine Liste von konkreten Zutaten mit Mengenangaben
   - Verständliche Zubereitungsschritte
2. Falls ein vollständiges Rezept vorliegt:
   - Setze `has_complete_recipe: true`
   - Extrahiere Titel, Zubereitungszeit (z.B. '25 Min.'), Portionen (Standard 4), Kategorie (eine von: 'Hauptgericht', 'Dessert', 'Frühstück', 'Snack', 'Backen')
   - Extrahiere alle Zutaten als Liste von Objekten mit numerischem 'amount' (z.B. 250, 1.5 oder null), 'unit' (z.B. 'g', 'ml', 'EL', 'TL', 'Stück' oder '') und 'name'
   - Extrahiere die Zubereitungsschritte auf Deutsch als Liste von Strings
3. Falls KEIN vollständiges Rezept in der Beschreibung steht (z.B. nur Teaser, unvollständige Zutaten oder der Hinweis 'Zubereitung im Video'):
   - Setze `has_complete_recipe: false` und belasse ingredients/instructions leer.
"""
        try:
            stage1_response = gemini_client.models.generate_content(
                model="gemini-2.5-flash",
                contents=[stage1_prompt],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=FastMetadataRecipeCheck,
                    temperature=0.2,
                ),
            )

            stage1_result: FastMetadataRecipeCheck = stage1_response.parsed
            if (
                stage1_result
                and stage1_result.has_complete_recipe
                and stage1_result.ingredients
                and len(stage1_result.ingredients) > 0
                and stage1_result.instructions
                and len(stage1_result.instructions) > 0
            ):
                logger.info("Stufe 1 erfolgreich: Vollständiges Rezept direkt aus Caption extrahiert (< 2s).")
                return RecipeResponse(
                    title=stage1_result.title or meta_title or "Rezept aus Video",
                    prep_time=stage1_result.prep_time or "25 Min.",
                    servings=stage1_result.servings or 4,
                    category=sanitize_category(stage1_result.category),
                    ingredients=stage1_result.ingredients,
                    instructions=stage1_result.instructions,
                    original_url=resolved_url,
                    source_platform=platform,
                    thumbnail_url=meta_thumbnail,
                )
            else:
                logger.info("Stufe 1: Caption enthält kein vollständiges Rezept. Wechsle zu Stufe 2 (Video-Download)...")
        except Exception as e:
            logger.warning(f"Fehler in Stufe 1 Gemini-Analyse: {e}. Wechsle zu Stufe 2...")

    # --- Stufe 2: Video-Download & Multimodale KI-Analyse ---
    logger.info("Stufe 2 aktiv: Starte temporären Video-Download und multimodale Analyse...")
    video_uuid = str(uuid.uuid4())
    temp_video_prefix = f"/tmp/{video_uuid}"
    ydl_download_opts = {
        "format": "best[ext=mp4]/best",
        "outtmpl": f"{temp_video_prefix}.%(ext)s",
        "quiet": True,
        "no_warnings": True,
        "max_filesize": 75 * 1024 * 1024,  # Maximal 75MB
    }

    downloaded_filepath = None
    uploaded_file = None

    try:
        with yt_dlp.YoutubeDL(ydl_download_opts) as ydl:
            download_info = ydl.extract_info(raw_url, download=True)
            if not resolved_url or resolved_url == raw_url:
                resolved_url = download_info.get("webpage_url") or raw_url
            if not meta_title:
                meta_title = download_info.get("title") or ""
            if not meta_thumbnail:
                meta_thumbnail = download_info.get("thumbnail")
            platform = detect_platform(resolved_url)

        # Finde heruntergeladene Datei (z. B. .mp4)
        matching_files = glob.glob(f"{temp_video_prefix}.*")
        if not matching_files:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Das Video konnte nicht heruntergeladen werden. Möglicherweise ist der Beitrag privat oder geschützt.",
            )
        downloaded_filepath = matching_files[0]
        logger.info(f"Video erfolgreich heruntergeladen: {downloaded_filepath} ({os.path.getsize(downloaded_filepath)} Bytes)")

        # Datei zu Gemini hochladen
        logger.info("Lade Video zu Gemini File API hoch...")
        uploaded_file = gemini_client.files.upload(file=downloaded_filepath)
        logger.info(f"Upload fertig. Datei-Name: {uploaded_file.name}, Status: {uploaded_file.state}")

        # Warten, falls Datei von Gemini verarbeitet wird
        poll_count = 0
        while uploaded_file.state and uploaded_file.state.name == "PROCESSING":
            time.sleep(2)
            uploaded_file = gemini_client.files.get(name=uploaded_file.name)
            poll_count += 1
            if poll_count > 30:
                raise HTTPException(
                    status_code=status.HTTP_504_GATEWAY_TIMEOUT,
                    detail="Zeitüberschreitung bei der Gemini-Videoverarbeitung.",
                )

        if uploaded_file.state and uploaded_file.state.name == "FAILED":
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Gemini konnte das Video nicht verarbeiten.",
            )

        logger.info("Video ist aktiv. Starte multimodale Inhaltsanalyse...")
        multimodal_prompt = f"""Du bist der kulinarische Chef-Analyst der Rezept-App 'Töpfle'.
Analysiere dieses Kochvideo sowie Ton, gesprochene Worte, Texteinblendungen und sichtbare Zubereitungsschritte.

Videotitel: {meta_title}
Videobeschreibung: {meta_description}

Deine Aufgabe:
Extrahiere ein präzises, deutsches Rezept aus dem Video:
1. `title`: Ein ansprechender, präziser Rezepttitel auf Deutsch.
2. `prep_time`: Geschätzte Gesamtzubereitungszeit (z. B. '20 Min.', '45 Min.').
3. `servings`: Typische Anzahl Portionen als Ganzzahl (Standard: 4).
4. `category`: Eine der folgenden Kategorien: 'Hauptgericht', 'Dessert', 'Frühstück', 'Snack', 'Backen'.
5. `ingredients`: Alle Zutaten mit:
   - `amount`: Numerischer Wert als Fließkommazahl (z. B. 250, 1.5, 0.5) oder null falls Mengenangabe nicht bestimmbar ist.
   - `unit`: Einheit (z. B. 'g', 'ml', 'EL', 'TL', 'Prise', 'Stück', oder leer falls Stückzahl/ohne).
   - `name`: Zutat (z. B. 'Weizenmehl', 'Milch', 'Knoblauch').
6. `instructions`: Chronologische, verständlich formulierte Zubereitungsschritte auf Deutsch.
"""

        stage2_response = gemini_client.models.generate_content(
            model="gemini-2.5-flash",
            contents=[uploaded_file, multimodal_prompt],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=MultimodalRecipeExtraction,
                temperature=0.2,
            ),
        )

        stage2_result: MultimodalRecipeExtraction = stage2_response.parsed
        if not stage2_result or not stage2_result.ingredients:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail="Im Video konnte kein verlässliches Rezept erkannt werden.",
            )

        logger.info("Stufe 2 erfolgreich abgeschlossen: Multimodales Rezept generiert.")
        return RecipeResponse(
            title=stage2_result.title or meta_title or "Rezept aus Video",
            prep_time=stage2_result.prep_time or "30 Min.",
            servings=stage2_result.servings or 4,
            category=sanitize_category(stage2_result.category),
            ingredients=stage2_result.ingredients,
            instructions=stage2_result.instructions,
            original_url=resolved_url,
            source_platform=platform,
            thumbnail_url=meta_thumbnail,
        )

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unerwarteter Fehler bei Stufe 2 Rezeptextraktion: {e}", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Fehler bei der Rezeptanalyse: {str(e)}",
        )
    finally:
        # Garantierte Bereinigung von lokalem Speicher und Gemini File API
        if uploaded_file and hasattr(uploaded_file, "name"):
            try:
                logger.info(f"Lösche Remote-Videodatei bei Gemini: {uploaded_file.name}")
                gemini_client.files.delete(name=uploaded_file.name)
            except Exception as del_err:
                logger.warning(f"Konnte Gemini-Datei {uploaded_file.name} nicht löschen: {del_err}")

        # Lokale temporäre Dateien löschen
        for f in glob.glob(f"{temp_video_prefix}.*"):
            try:
                logger.info(f"Lösche lokale temporäre Videodatei: {f}")
                os.remove(f)
            except Exception as f_err:
                logger.warning(f"Konnte temporäre Datei {f} nicht löschen: {f_err}")
