#!/bin/bash

set -e

echo "🔄 Mise à jour de Mahrasoft.com"
echo "==============================="

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Vérifier que Git est installé
if ! command -v git &> /dev/null; then
    log_error "Git n'est pas installé"
    exit 1
fi

# Demander confirmation
echo ""
log_warn "Cette opération va:"
echo "   1. Récupérer les dernières modifications depuis Git"
echo "   2. Reconstruire les images Docker"
echo "   3. Redémarrer tous les services"
echo ""
read -p "Voulez-vous continuer ? (Y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
    log_info "Mise à jour annulée"
    exit 0
fi

# Sauvegarder l'état actuel
log_info "Sauvegarde de la configuration actuelle..."
BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

# Copier les fichiers importants
cp -r Backend/app/main.py "$BACKUP_DIR/" 2>/dev/null || true
cp .env "$BACKUP_DIR/" 2>/dev/null || true
cp -r Backend/nginx/ssl "$BACKUP_DIR/" 2>/dev/null || true

log_info "✅ Backup créé dans: $BACKUP_DIR"

# Vérifier les modifications locales
if [[ -n $(git status -s) ]]; then
    log_warn "Vous avez des modifications locales non committées"
    git status -s
    echo ""
    read -p "Voulez-vous les sauvegarder avant de continuer ? (Y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        git stash push -m "Auto-stash avant mise à jour $(date +%Y%m%d_%H%M%S)"
        log_info "✅ Modifications sauvegardées avec git stash"
    fi
fi

# Pull des dernières modifications Git
log_info "Récupération des dernières modifications depuis Git..."
BRANCH=$(git branch --show-current)
log_info "Branche actuelle: $BRANCH"

if git pull origin "$BRANCH"; then
    log_info "✅ Code source mis à jour"
else
    log_error "Échec du pull Git"
    exit 1
fi

# Vérifier si des dépendances ont changé
if git diff HEAD@{1} HEAD -- Backend/app/requirements.txt | grep -q '^[+-][^+-]'; then
    log_warn "Le fichier requirements.txt a été modifié"
    log_info "Les dépendances Python seront mises à jour"
fi

# Reconstruire les images Docker
log_info "Reconstruction des images Docker..."
if docker compose build --no-cache; then
    log_info "✅ Images Docker reconstruites"
else
    log_error "Échec de la reconstruction des images"
    exit 1
fi

# Arrêter les services
log_info "Arrêt des services..."
docker compose down

# Nettoyer
log_info "Nettoyage des ressources inutilisées..."
docker system prune -f

# Redémarrer les services
log_info "Redémarrage des services..."
docker compose up -d

# Attendre le démarrage du backend
log_info "Attente du démarrage du backend..."
timeout=60
counter=0
until docker compose exec mahrasoft-backend curl -sf http://localhost:8000/health > /dev/null 2>&1; do
    counter=$((counter + 1))
    if [ $counter -gt $timeout ]; then
        log_error "Timeout: Le backend ne démarre pas"
        log_error "Logs du backend:"
        docker compose logs --tail=50 mahrasoft-backend
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""
log_info "✅ Backend démarré"

# Attendre Nginx
sleep 5

# Vérifier le statut
log_info "Vérification du statut des services..."
docker compose ps

# Test du health check
log_info "Test du health check..."
if curl -k -sf https://localhost/health > /dev/null 2>&1; then
    log_info "✅ Health check OK"
else
    log_warn "⚠️  Health check échoué, vérification des logs..."
    docker compose logs --tail=20 mahrasoft-backend
fi

echo ""
echo "========================================="
log_info "✅ Mise à jour terminée avec succès !"
echo "========================================="
echo ""
log_info "📊 Résumé:"
echo "   - Backup: $BACKUP_DIR"
echo "   - Branche: $BRANCH"
echo "   - Commit: $(git rev-parse --short HEAD)"
echo ""
log_info "🌐 Votre site est accessible sur:"
echo "   - https://mahrasoft.com"
echo ""
log_info "📋 Pour voir les logs: docker compose logs -f"
echo ""
