"""
Mahrasoft.com — main.py (version optimisée pour la performance)
================================================================
Optimisations appliquées :
  1. GZipMiddleware  — compression automatique des réponses HTML/JSON/CSS/JS
  2. En-têtes Cache-Control sur les fichiers statiques (via middleware)
  3. Routes /health et /ping dédupliquées (une seule définition chacune)
  4. Lifespan remplace les @on_event dépréciés (FastAPI ≥ 0.93)
  5. Chargement des posts en dehors du lifespan pour éviter les re-lectures
  6. Imports rangés (stdlib → tiers → local)
  FIX : Nouvelle API Starlette 0.36+ — TemplateResponse(request, name, context)
================================================================
"""

from __future__ import annotations

import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.base import BaseHTTPMiddleware

# ──────────────────────────────────────────────────────────────────────────────
# CHEMINS ABSOLUS
# ──────────────────────────────────────────────────────────────────────────────
BASE_DIR      = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR    = os.path.join(BASE_DIR, "static")
TEMPLATES_DIR = os.path.join(BASE_DIR, "templates")
DB_FILE       = os.path.join(BASE_DIR, "db.json")

os.makedirs(STATIC_DIR, exist_ok=True)
os.makedirs(TEMPLATES_DIR, exist_ok=True)

# ──────────────────────────────────────────────────────────────────────────────
# LOGGING
# ──────────────────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger("mahrasoft")

# ──────────────────────────────────────────────────────────────────────────────
# DONNÉES (chargées une seule fois au démarrage du process)
# ──────────────────────────────────────────────────────────────────────────────
def _load_posts() -> list[dict]:
    try:
        with open(DB_FILE, "r", encoding="utf-8") as f:
            data  = json.load(f)
            posts = data.get("posts", [])
            logger.info("✅ %d offres d'emploi chargées", len(posts))
            return posts
    except FileNotFoundError:
        logger.warning("⚠️  db.json introuvable : %s", DB_FILE)
        return []
    except json.JSONDecodeError as exc:
        logger.error("❌ JSON invalide dans db.json : %s", exc)
        return []


posts: list[dict] = _load_posts()

# ──────────────────────────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────────────────────────
def https_url_for(request: Request, name: str, **path_params) -> str:
    try:
        url = str(request.url_for(name, **path_params))
        proto = request.headers.get("x-forwarded-proto", "")
        if proto == "https" or os.getenv("ENVIRONMENT", "development").lower() == "production":
            url = url.replace("http://", "https://", 1)
        return url
    except Exception as exc:
        logger.debug("https_url_for error: %s", exc)
        return f"/static/{path_params.get('path', '')}"

# ──────────────────────────────────────────────────────────────────────────────
# MIDDLEWARE — Cache-Control sur les statiques
# ──────────────────────────────────────────────────────────────────────────────
class StaticCacheMiddleware(BaseHTTPMiddleware):
    _LONG_CACHE  = "public, max-age=604800, immutable"
    _NO_CACHE    = "no-cache, no-store, must-revalidate"
    _SHORT_CACHE = "public, max-age=3600"
    _STATIC_EXTS = {".css", ".js", ".woff", ".woff2", ".ttf", ".eot",
                    ".ico", ".png", ".jpg", ".jpeg", ".gif", ".svg", ".webp"}

    async def dispatch(self, request: Request, call_next) -> Response:
        response = await call_next(request)
        path = request.url.path
        ext  = os.path.splitext(path)[1].lower()
        if path.startswith("/static/"):
            if ext in self._STATIC_EXTS:
                response.headers["Cache-Control"] = self._LONG_CACHE
            else:
                response.headers["Cache-Control"] = self._SHORT_CACHE
        elif path in ("/health", "/ping"):
            response.headers["Cache-Control"] = self._NO_CACHE
        elif response.headers.get("content-type", "").startswith("text/html"):
            response.headers["Cache-Control"] = self._NO_CACHE
        return response

# ──────────────────────────────────────────────────────────────────────────────
# LIFESPAN
# ──────────────────────────────────────────────────────────────────────────────
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("=" * 60)
    logger.info("🚀 Démarrage Mahrasoft.com")
    logger.info("   BASE_DIR   : %s", BASE_DIR)
    logger.info("   STATIC_DIR : %s", STATIC_DIR)
    logger.info("   TEMPLATES  : %s", TEMPLATES_DIR)
    logger.info("   DB_FILE    : %s", DB_FILE)
    logger.info("   Posts      : %d", len(posts))
    logger.info("=" * 60)
    yield
    logger.info("🛑 Arrêt Mahrasoft.com")

# ──────────────────────────────────────────────────────────────────────────────
# APPLICATION
# ──────────────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="Mahrasoft.com API",
    description="API pour le site web Mahrasoft Innovations",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)

app.add_middleware(GZipMiddleware, minimum_size=500)
app.add_middleware(StaticCacheMiddleware)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")

# ── Templates (instance unique) ───────────────────────────────────────────────
templates = Jinja2Templates(directory=TEMPLATES_DIR)
templates.env.globals["https_url_for"] = https_url_for

# ── Logging des requêtes ──────────────────────────────────────────────────────
@app.middleware("http")
async def log_requests(request: Request, call_next):
    t0       = datetime.now()
    response = await call_next(request)
    ms       = (datetime.now() - t0).total_seconds() * 1000
    logger.info("%s %s → %d (%.1f ms)", request.method, request.url.path, response.status_code, ms)
    return response

# ──────────────────────────────────────────────────────────────────────────────
# HEALTH CHECK
# ──────────────────────────────────────────────────────────────────────────────
@app.get("/health", tags=["Health"])
async def health_check():
    return {
        "status":      "healthy",
        "service":     "Mahrasoft.com",
        "timestamp":   datetime.now().isoformat(),
        "version":     "1.0.0",
        "posts_count": len(posts),
    }

@app.get("/ping", tags=["Health"])
async def ping():
    return {"status": "ok", "message": "pong", "timestamp": datetime.now().isoformat()}

# ──────────────────────────────────────────────────────────────────────────────
# PAGES PRINCIPALES
# FIX : nouvelle API Starlette — TemplateResponse(request, name, context)
# ──────────────────────────────────────────────────────────────────────────────
@app.get("/", response_class=HTMLResponse, tags=["Pages"])
async def index(request: Request):
    return templates.TemplateResponse(request, "index.html", {"current": "index"})

@app.get("/about", response_class=HTMLResponse, tags=["Pages"])
async def about(request: Request):
    return templates.TemplateResponse(request, "about.html", {"current": "about"})

@app.get("/service", response_class=HTMLResponse, tags=["Pages"])
async def service(request: Request):
    return templates.TemplateResponse(request, "service.html", {"current": "service"})

@app.get("/blog", response_class=HTMLResponse, tags=["Pages"])
async def blog(request: Request):
    return templates.TemplateResponse(request, "blog.html", {"current": "blog"})

@app.get("/detail", response_class=HTMLResponse, tags=["Pages"])
async def detail(request: Request):
    return templates.TemplateResponse(request, "detail.html", {"current": "detail"})

@app.get("/contact", response_class=HTMLResponse, tags=["Pages"])
async def contact(request: Request):
    return templates.TemplateResponse(request, "contact.html", {"current": "contact"})

# ──────────────────────────────────────────────────────────────────────────────
# SECTION DÉCOUVREZ
# ──────────────────────────────────────────────────────────────────────────────
@app.get("/decouvrez/valeurs", response_class=HTMLResponse, tags=["Découvrez"])
async def valeurs(request: Request):
    return templates.TemplateResponse(request, "valeurs.html", {"current": "valeurs"})

@app.get("/decouvrez/clients", response_class=HTMLResponse, tags=["Découvrez"])
async def clients(request: Request):
    return templates.TemplateResponse(request, "clients.html", {"current": "clients"})

@app.get("/decouvrez/strategie", response_class=HTMLResponse, tags=["Découvrez"])
async def strategie(request: Request):
    return templates.TemplateResponse(request, "strategie.html", {"current": "strategie"})

# ──────────────────────────────────────────────────────────────────────────────
# SECTION CARRIÈRES
# ──────────────────────────────────────────────────────────────────────────────
@app.get("/carrieres/rechercherpostuler", response_class=HTMLResponse, tags=["Carrières"])
async def rechercher_postuler(request: Request):
    return templates.TemplateResponse(
        request,
        "rechercherpostuler.html",
        {"current": "rechercherpostuler", "posts": posts},
    )

@app.get("/carrieres/job/{id}", response_class=HTMLResponse, tags=["Carrières"])
async def job(id: str, request: Request):
    post = next((p for p in posts if p["id"] == id), None)
    if post:
        return templates.TemplateResponse(request, "job.html", {"post": post})
    return templates.TemplateResponse(request, "404.html", status_code=404)

@app.get("/carrieres/jeunediplomes", response_class=HTMLResponse, tags=["Carrières"])
async def jeune_diplomes(request: Request):
    return templates.TemplateResponse(request, "jeunediplomes.html", {"current": "jeunediplomes"})

@app.get("/carrieres/etudiants", response_class=HTMLResponse, tags=["Carrières"])
async def etudiants(request: Request):
    return templates.TemplateResponse(request, "etudiants.html", {"current": "etudiants"})

@app.get("/carrieres/formation", response_class=HTMLResponse, tags=["Carrières"])
async def formation(request: Request):
    return templates.TemplateResponse(request, "formation.html", {"current": "formation"})

@app.get("/carrieres/environnementdetravail", response_class=HTMLResponse, tags=["Carrières"])
async def environnement_travail(request: Request):
    return templates.TemplateResponse(
        request,
        "environnementdetravail.html",
        {"current": "environnementdetravail"},
    )

# ──────────────────────────────────────────────────────────────────────────────
# ERROR HANDLERS
# ──────────────────────────────────────────────────────────────────────────────
@app.exception_handler(404)
async def not_found(request: Request, exc: HTTPException):
    if request.url.path.startswith("/api"):
        return JSONResponse(
            status_code=404,
            content={"error": "Not Found", "path": request.url.path, "timestamp": datetime.now().isoformat()},
        )
    return templates.TemplateResponse(request, "404.html", status_code=404)

@app.exception_handler(500)
async def server_error(request: Request, exc: Exception):
    logger.error("Erreur 500 sur %s : %s", request.url.path, exc)
    return JSONResponse(
        status_code=500,
        content={"error": "Internal Server Error", "timestamp": datetime.now().isoformat()},
    )