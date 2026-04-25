#!/bin/bash
# =============================================================
# Backend/build/entrypoint.sh — mahrasoft.com
# =============================================================

set -e
# NOTE : on n'utilise PAS set -u car RELOAD_OPT peut être vide
# et bash -u interprète une variable vide comme non définie

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# ── Variables d'environnement ──────────────────────────────
log_info "🔍 Vérification des variables d'environnement..."
if [ -z "${SECRET_KEY:-}" ]; then
  log_warn "⚠️  SECRET_KEY non défini (valeur par défaut utilisée)"
fi
log_info "✅ Variables vérifiées"

# ── Dossiers montés en volumes (uploads, temp, logs) ───────
# ⚠️  NE PAS créer /mahrasoft-app/static ici — il est baked
#     dans l'image par COPY app/ . dans le Dockerfile.
#     Créer static ici écraserait les fichiers de l'image.
log_info "📁 Initialisation des dossiers de données..."

for dir in \
  "/mahrasoft-app/uploads/img" \
  "/mahrasoft-app/uploads/documents" \
  "/mahrasoft-app/uploads/media" \
  "/mahrasoft-app/uploads/temp" \
  "/mahrasoft-app/temp" \
  "/mahrasoft-app/logs"
do
  mkdir -p "$dir"
  log_debug "✓ $dir"
done

if [ "${APP_DEBUG:-False}" = "True" ]; then
  chmod -R 777 /mahrasoft-app/uploads /mahrasoft-app/temp 2>/dev/null || true
  log_warn "⚠️  Permissions permissives (mode DEBUG)"
else
  chmod -R 755 /mahrasoft-app/uploads /mahrasoft-app/temp 2>/dev/null || true
  log_info "✅ Permissions sécurisées (mode PRODUCTION)"
fi
log_info "✅ Dossiers de données initialisés"

# ── Vérification des fichiers statiques ────────────────────
log_info "🔍 Vérification des fichiers statiques..."

if [ ! -d "/mahrasoft-app/static" ]; then
  log_error "❌ CRITIQUE : /mahrasoft-app/static absent !"
  log_error "   Cause : un volume docker-compose monte un dossier vide"
  log_error "   sur /mahrasoft-app/static et écrase les fichiers de l'image."
  log_error "   Solution : retirer le volume static du docker-compose.yml"
  exit 1
fi

STATIC_COUNT=$(find /mahrasoft-app/static -type f 2>/dev/null | wc -l)
if [ "$STATIC_COUNT" -eq 0 ]; then
  log_error "❌ CRITIQUE : /mahrasoft-app/static est VIDE !"
  log_error "   Solution : retirer le volume static du docker-compose.yml"
  exit 1
fi
log_info "✅ Fichiers statiques présents : $STATIC_COUNT fichier(s)"

# ── Vérification de main.py ────────────────────────────────
log_info "🔍 Vérification de l'application..."
if [ ! -f "/mahrasoft-app/main.py" ]; then
  log_error "❌ main.py introuvable dans /mahrasoft-app"
  ls -la /mahrasoft-app
  exit 1
fi
log_info "✅ main.py trouvé"

if python -c "import main" 2>/dev/null; then
  log_info "✅ Import Python réussi"
else
  log_error "❌ Échec de l'import Python :"
  python -c "import main" || true
  exit 1
fi

# ── Configuration du lancement ─────────────────────────────
log_info "⚙️  Configuration :"
log_info "   Environment : ${ENVIRONMENT:-production}"
log_info "   Debug       : ${APP_DEBUG:-False}"
log_info "   Workers     : ${NB_WORKERS:-2}"
log_info "   Static files: $STATIC_COUNT fichier(s)"

# FIX set -eu : initialiser RELOAD_OPT avant d'utiliser set -u
# Une variable vide avec set -u provoque : "unbound variable"
RELOAD_OPT=""
LOG_LEVEL="info"

if [ "${APP_DEBUG:-False}" = "True" ]; then
  RELOAD_OPT="--reload"
  LOG_LEVEL="debug"
  log_warn "🚧 Mode DEBUG activé (auto-reload)"
else
  log_info "🚀 Mode PRODUCTION"
fi

# ── Lancement ──────────────────────────────────────────────
log_info "🚀 Démarrage de mahrasoft.com sur http://0.0.0.0:8000"
log_info "   Workers : ${NB_WORKERS:-2}"

cd /mahrasoft-app

# shellcheck disable=SC2086
exec gunicorn \
  --workers "${NB_WORKERS:-2}" \
  --worker-class uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8000 \
  --timeout 120 \
  --keep-alive 5 \
  --log-level "$LOG_LEVEL" \
  --access-logfile /mahrasoft-app/logs/access.log \
  --error-logfile /mahrasoft-app/logs/error.log \
  --capture-output \
  --enable-stdio-inheritance \
  $RELOAD_OPT \
  main:app