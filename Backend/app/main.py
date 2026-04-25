"""
Mahrasoft.com — main.py
================================================================
CORRECTIONS APPLIQUÉES :
1. Correction complète de TemplateResponse pour compatibilité
   avec FastAPI/Starlette actuelle installée sur ton VPS

   Ancienne erreur :
   TemplateResponse(
       request=request,
       name="index.html",
       context={}
   )

   Nouvelle syntaxe correcte :
   TemplateResponse(
       "index.html",
       {"request": request}
   )

2. Correction route /carrieres/job/{id}

3. Correction handler 404

4. Conservation du cache static

5. Conservation du logging

6. Conservation du support HTTPS derrière reverse proxy
================================================================
"""

from __future__ import annotations

import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from starlette.middleware.base import BaseHTTPMiddleware


# =========================================================
# CHEMINS
# =========================================================
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
STATIC_DIR = os.path.join(BASE_DIR, "static")
TEMPLATES_DIR = os.path.join(BASE_DIR, "templates")
DB_FILE = os.path.join(BASE_DIR, "db.json")

os.makedirs(STATIC_DIR, exist_ok=True)
os.makedirs(TEMPLATES_DIR, exist_ok=True)


# =========================================================
# LOGGING
# =========================================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)

logger = logging.getLogger("mahrasoft")


# =========================================================
# CHARGEMENT DES POSTS
# =========================================================
def load_posts() -> list[dict]:
    try:
        with open(DB_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
            posts = data.get("posts", [])
            logger.info("✅ %d offres chargées", len(posts))
            return posts

    except FileNotFoundError:
        logger.warning("⚠️ db.json introuvable : %s", DB_FILE)
        return []

    except json.JSONDecodeError as e:
        logger.error("❌ JSON invalide : %s", e)
        return []


posts = load_posts()


# =========================================================
# HTTPS URL HELPER
# =========================================================
def https_url_for(request: Request, name: str, **path_params):
    try:
        url = str(request.url_for(name, **path_params))

        proto = request.headers.get("x-forwarded-proto", "")

        if (
            proto == "https"
            or os.getenv("ENVIRONMENT", "development").lower() == "production"
        ):
            url = url.replace("http://", "https://", 1)

        return url

    except Exception as e:
        logger.debug("Erreur https_url_for: %s", e)
        return f"/static/{path_params.get('path', '')}"


# =========================================================
# CACHE STATIC
# =========================================================
class StaticCacheMiddleware(BaseHTTPMiddleware):
    LONG_CACHE = "public, max-age=604800, immutable"
    SHORT_CACHE = "public, max-age=3600"
    NO_CACHE = "no-cache, no-store, must-revalidate"

    STATIC_EXTENSIONS = {
        ".css",
        ".js",
        ".woff",
        ".woff2",
        ".ttf",
        ".eot",
        ".ico",
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".svg",
        ".webp",
    }

    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)

        path = request.url.path
        ext = os.path.splitext(path)[1].lower()

        if path.startswith("/static/"):
            if ext in self.STATIC_EXTENSIONS:
                response.headers["Cache-Control"] = self.LONG_CACHE
            else:
                response.headers["Cache-Control"] = self.SHORT_CACHE

        elif path in ["/health", "/ping"]:
            response.headers["Cache-Control"] = self.NO_CACHE

        elif response.headers.get("content-type", "").startswith("text/html"):
            response.headers["Cache-Control"] = self.NO_CACHE

        return response


# =========================================================
# LIFESPAN
# =========================================================
@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("=" * 50)
    logger.info("🚀 Démarrage Mahrasoft")
    logger.info("BASE_DIR: %s", BASE_DIR)
    logger.info("STATIC_DIR: %s", STATIC_DIR)
    logger.info("TEMPLATES_DIR: %s", TEMPLATES_DIR)
    logger.info("DB_FILE: %s", DB_FILE)
    logger.info("Posts chargés: %d", len(posts))
    logger.info("=" * 50)

    yield

    logger.info("🛑 Arrêt Mahrasoft")


# =========================================================
# APP
# =========================================================
app = FastAPI(
    title="Mahrasoft API",
    version="1.0.0",
    lifespan=lifespan
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


# =========================================================
# TEMPLATES
# =========================================================
templates = Jinja2Templates(directory=TEMPLATES_DIR)
templates.env.globals["https_url_for"] = https_url_for


# =========================================================
# LOG REQUESTS
# =========================================================
@app.middleware("http")
async def log_requests(request: Request, call_next):
    start = datetime.now()

    response = await call_next(request)

    duration = (datetime.now() - start).total_seconds() * 1000

    logger.info(
        "%s %s -> %s (%.2f ms)",
        request.method,
        request.url.path,
        response.status_code,
        duration
    )

    return response


# =========================================================
# HEALTH
# =========================================================
@app.get("/health")
async def health():
    return {
        "status": "healthy",
        "timestamp": datetime.now().isoformat(),
        "posts_count": len(posts)
    }


@app.get("/ping")
async def ping():
    return {"message": "pong"}


# =========================================================
# PAGES
# =========================================================
@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    return templates.TemplateResponse(
        "index.html",
        {"request": request, "current": "index"}
    )


@app.get("/about")
async def about(request: Request):
    return templates.TemplateResponse(
        "about.html",
        {"request": request, "current": "about"}
    )


@app.get("/service")
async def service(request: Request):
    return templates.TemplateResponse(
        "service.html",
        {"request": request, "current": "service"}
    )


@app.get("/blog")
async def blog(request: Request):
    return templates.TemplateResponse(
        "blog.html",
        {"request": request, "current": "blog"}
    )


@app.get("/detail")
async def detail(request: Request):
    return templates.TemplateResponse(
        "detail.html",
        {"request": request, "current": "detail"}
    )


@app.get("/contact")
async def contact(request: Request):
    return templates.TemplateResponse(
        "contact.html",
        {"request": request, "current": "contact"}
    )


# =========================================================
# DECOUVREZ
# =========================================================
@app.get("/decouvrez/valeurs")
async def valeurs(request: Request):
    return templates.TemplateResponse(
        "valeurs.html",
        {"request": request}
    )


@app.get("/decouvrez/clients")
async def clients(request: Request):
    return templates.TemplateResponse(
        "clients.html",
        {"request": request}
    )


@app.get("/decouvrez/strategie")
async def strategie(request: Request):
    return templates.TemplateResponse(
        "strategie.html",
        {"request": request}
    )


# =========================================================
# CARRIERES
# =========================================================
@app.get("/carrieres/rechercherpostuler")
async def rechercher_postuler(request: Request):
    return templates.TemplateResponse(
        "rechercherpostuler.html",
        {
            "request": request,
            "posts": posts
        }
    )


@app.get("/carrieres/job/{id}")
async def job(id: str, request: Request):
    post = next((p for p in posts if p["id"] == id), None)

    if post:
        return templates.TemplateResponse(
            "job.html",
            {
                "request": request,
                "post": post
            }
        )

    return templates.TemplateResponse(
        "404.html",
        {
            "request": request
        },
        status_code=404
    )


@app.get("/carrieres/jeunediplomes")
async def jeunes(request: Request):
    return templates.TemplateResponse(
        "jeunediplomes.html",
        {"request": request}
    )


@app.get("/carrieres/etudiants")
async def etudiants(request: Request):
    return templates.TemplateResponse(
        "etudiants.html",
        {"request": request}
    )


@app.get("/carrieres/formation")
async def formation(request: Request):
    return templates.TemplateResponse(
        "formation.html",
        {"request": request}
    )


@app.get("/carrieres/environnementdetravail")
async def environnement(request: Request):
    return templates.TemplateResponse(
        "environnementdetravail.html",
        {"request": request}
    )


# =========================================================
# ERROR HANDLERS
# =========================================================
@app.exception_handler(404)
async def not_found(request: Request, exc):
    if request.url.path.startswith("/api"):
        return JSONResponse(
            status_code=404,
            content={
                "error": "Not Found",
                "path": request.url.path,
                "timestamp": datetime.now().isoformat()
            }
        )

    return templates.TemplateResponse(
        "404.html",
        {"request": request},
        status_code=404
    )


@app.exception_handler(500)
async def server_error(request: Request, exc: Exception):
    logger.error(
        "Erreur 500 sur %s : %s",
        request.url.path,
        str(exc)
    )

    return JSONResponse(
        status_code=500,
        content={
            "error": "Internal Server Error",
            "timestamp": datetime.now().isoformat()
        }
    )