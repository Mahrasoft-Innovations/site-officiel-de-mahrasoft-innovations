#!/bin/bash
# =============================================================
# Backend/scripts/deploy.sh — mahrasoft.com
#
# FIXES :
#   1. Ne crée PLUS /mnt/storage/docker/mahrasoft/static
#      (ce volume vide écrasait les statiques de l'image)
#   2. Ne crée PLUS main.py.backup
#      (causait des conflits Git à chaque déploiement)
#   3. Ne modifie PLUS main.py automatiquement
#      (les endpoints /health et /ping sont déjà dans le code)
# =============================================================

set -e

echo "🚀 Déploiement de Mahrasoft.com"
echo "================================"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error(){ echo -e "${RED}[ERROR]${NC} $1"; }
log_debug(){ echo -e "${BLUE}[DEBUG]${NC} $1"; }

# ── Prérequis ─────────────────────────────────────────────
log_info "Vérification de l'environnement..."

command -v docker       &>/dev/null || { log_error "Docker non installé";         exit 1; }
command -v docker compose &>/dev/null || { log_error "Docker Compose non installé"; exit 1; }

[ -f ".env" ] || log_warn "Fichier .env absent (optionnel)"
[ -f "Backend/app/main.py" ] || { log_error "Backend/app/main.py introuvable"; exit 1; }

# ── Vérification /health (sans modifier main.py) ──────────
if grep -q '"/health"' Backend/app/main.py 2>/dev/null; then
  log_info "✅ Endpoint /health présent dans main.py"
else
  log_warn "⚠️  Endpoint /health absent — vérifiez Backend/app/main.py"
fi

# ── Certificats SSL ───────────────────────────────────────
if [ ! -f "Backend/nginx/ssl/cert.pem" ] || [ ! -f "Backend/nginx/ssl/key.pem" ]; then
  log_warn "Certificats SSL non trouvés"
  read -rp "Les générer maintenant ? (Y/n) " reply
  [[ "${reply:-Y}" =~ ^[Yy]$ ]] || { log_error "Certificats SSL requis"; exit 1; }
  chmod +x Backend/scripts/setup_ssl.sh
  ./Backend/scripts/setup_ssl.sh
fi

# ── Dossiers de données (volumes Docker) ──────────────────
# ⚠️  NE PAS créer /static ici — il est baked dans l'image Docker.
#    Seuls uploads, temp et logs sont des volumes persistés.
log_info "Création des dossiers de données persistés..."

mkdir -p logs/nginx
mkdir -p Backend/nginx/ssl

STORAGE_PATH="/mnt/storage/docker/mahrasoft"

create_storage_dirs() {
  local base="$1"
  mkdir -p "$base/uploads"
  # FIX : PAS de mkdir static — le volume static a été retiré du docker-compose
  # mkdir -p "$base/static"  ← SUPPRIMÉ (causait le bug images)
  mkdir -p "$base/temp"
  mkdir -p "$base/logs"
  chmod -R 755 "$base"
  log_info "✅ Dossiers créés dans $base"
}

if [ ! -d "/mnt/storage" ]; then
  log_warn "/mnt/storage inexistant"
  echo "1) Créer /mnt/storage avec sudo"
  echo "2) Utiliser ~/docker/mahrasoft"
  read -rp "Choix (1 ou 2) : " storage_choice
  case $storage_choice in
    1)
      sudo mkdir -p /mnt/storage
      sudo chown -R "$USER:$USER" /mnt/storage
      create_storage_dirs "$STORAGE_PATH"
      ;;
    2)
      STORAGE_PATH="$HOME/docker/mahrasoft"
      create_storage_dirs "$STORAGE_PATH"
      log_warn "Mettez à jour docker-compose.yml avec : $STORAGE_PATH"
      ;;
    *)
      log_error "Choix invalide"; exit 1 ;;
  esac
else
  if [ -w "/mnt/storage" ]; then
    create_storage_dirs "$STORAGE_PATH"
  else
    sudo mkdir -p "$STORAGE_PATH"
    sudo chown -R "$USER:$USER" "$STORAGE_PATH"
    create_storage_dirs "$STORAGE_PATH"
  fi
fi

# ── Logs nginx ────────────────────────────────────────────
log_info "Configuration des permissions des logs..."
mkdir -p logs/nginx
chmod 755 logs logs/nginx 2>/dev/null || sudo chmod 755 logs logs/nginx
log_info "✅ Permissions logs configurées"

# ── Déploiement ───────────────────────────────────────────
log_info "Arrêt des conteneurs existants..."
docker compose down 2>/dev/null || true

log_info "Nettoyage Docker..."
docker system prune -f

log_info "Construction de l'image..."
docker compose build --no-cache

log_info "Démarrage du backend..."
docker compose up -d mahrasoft-backend

log_info "Attente du démarrage..."
timeout=60
counter=0
until docker compose exec mahrasoft-backend curl -sf http://localhost:8000/health >/dev/null 2>&1; do
  counter=$((counter + 1))
  [ $counter -gt $timeout ] && {
    log_error "Timeout — logs du backend :"
    docker compose logs mahrasoft-backend
    exit 1
  }
  printf "."
  sleep 2
done
echo ""
log_info "✅ Backend démarré"

log_info "Démarrage de Nginx..."
docker compose up -d nginx
sleep 5

# ── Tests ─────────────────────────────────────────────────
log_info "Vérification du statut..."
docker compose ps

http_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null || echo "000")
[[ "$http_code" =~ ^30[12]$ ]] \
  && log_info "✅ HTTP → HTTPS redirect OK" \
  || log_warn "⚠️  Redirection HTTP : code $http_code"

https_code=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost/health 2>/dev/null || echo "000")
[ "$https_code" = "200" ] \
  && log_info "✅ HTTPS /health OK" \
  || log_warn "⚠️  HTTPS /health : code $https_code"

# ── Résumé ────────────────────────────────────────────────
echo ""
echo "========================================="
log_info "✅ Déploiement terminé !"
echo "========================================="
echo ""
echo "🌐 URLs :"
echo "   https://mahrasoft.com"
echo "   https://mahrasoft.com/health"
echo ""
echo "📊 Commandes utiles :"
echo "   docker compose logs -f mahrasoft-backend"
echo "   docker compose logs -f nginx"
echo "   docker compose ps"
echo "   docker compose down"
echo "   docker compose restart"
echo ""
log_info "📁 Stockage : $STORAGE_PATH"
log_info "🎉 mahrasoft.com est en ligne !"