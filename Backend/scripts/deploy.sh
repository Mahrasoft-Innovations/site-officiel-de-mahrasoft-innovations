#!/bin/bash

set -e

echo "🚀 Déploiement de Mahrasoft.com"
echo "================================"

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Vérifications préalables
log_info "Vérification de l'environnement..."

# Docker
if ! command -v docker &> /dev/null; then
    log_error "Docker n'est pas installé"
    exit 1
fi

# Docker Compose
if ! command -v docker compose &> /dev/null; then
    log_error "Docker Compose n'est pas installé"
    exit 1
fi

# Fichier .env (optionnel pour ce projet)
if [ ! -f ".env" ]; then
    log_warn "Le fichier .env n'existe pas (optionnel)"
    log_info "Vous pouvez créer un fichier .env si nécessaire"
fi

# Vérifier que l'endpoint /health existe
log_info "Vérification de l'endpoint /health dans main.py..."
if [ ! -f "Backend/app/main.py" ]; then
    log_error "Le fichier Backend/app/main.py n'existe pas"
    exit 1
fi

if ! grep -q "@app.get(\"/health\")" Backend/app/main.py && ! grep -q "@app.get('/health')" Backend/app/main.py; then
    log_warn "L'endpoint /health n'existe pas dans main.py"
    echo ""
    echo "Voulez-vous que je l'ajoute automatiquement ? (Y/n)"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]] || [[ -z "$response" ]]; then
        log_info "Ajout des endpoints /health et /ping..."
        
        # Créer un backup
        cp Backend/app/main.py Backend/app/main.py.backup
        
        # Ajouter les endpoints
        cat >> Backend/app/main.py << 'EOF'

# ================================
# Health Check Endpoints
# ================================
from datetime import datetime

@app.get("/health")
async def health_check():
    """Endpoint de santé pour Docker health check et monitoring"""
    return {
        "status": "healthy",
        "service": "Mahrasoft.com",
        "timestamp": datetime.now().isoformat(),
        "version": "1.0.0"
    }

@app.get("/ping")
async def ping():
    """Simple ping endpoint pour vérifier que le service répond"""
    return {
        "status": "ok",
        "message": "pong",
        "timestamp": datetime.now().isoformat()
    }
EOF
        
        log_info "✅ Endpoints /health et /ping ajoutés avec succès"
        log_info "📁 Backup sauvegardé: Backend/app/main.py.backup"
    else
        log_warn "Continuons sans ajouter les endpoints..."
    fi
fi

# Certificats SSL
if [ ! -f "Backend/nginx/ssl/cert.pem" ] || [ ! -f "Backend/nginx/ssl/key.pem" ]; then
    log_warn "Certificats SSL non trouvés"
    read -p "Voulez-vous les générer maintenant ? (Y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        chmod +x Backend/scripts/setup_ssl.sh
        ./Backend/scripts/setup_ssl.sh
    else
        log_error "Les certificats SSL sont nécessaires pour le déploiement"
        exit 1
    fi
fi

# ==========================================
# CRÉATION DES DOSSIERS AVEC GESTION DES PERMISSIONS
# ==========================================
log_info "Création des dossiers nécessaires..."

# Créer le dossier logs local
mkdir -p logs/nginx
mkdir -p Backend/nginx/ssl

# Définir le chemin de stockage
STORAGE_PATH="/mnt/storage/docker/mahrasoft"

# Vérifier si /mnt/storage existe
if [ ! -d "/mnt/storage" ]; then
    log_warn "Le dossier /mnt/storage n'existe pas"
    echo ""
    echo "Choisissez une option :"
    echo "1) Créer /mnt/storage avec sudo (recommandé)"
    echo "2) Utiliser un chemin alternatif (~/docker/mahrasoft)"
    echo ""
    read -p "Votre choix (1 ou 2) : " storage_choice
    
    case $storage_choice in
        1)
            log_info "Création de /mnt/storage avec sudo..."
            sudo mkdir -p /mnt/storage/docker/mahrasoft/uploads
            sudo mkdir -p /mnt/storage/docker/mahrasoft/static
            sudo chown -R $USER:$USER /mnt/storage/docker/mahrasoft
            sudo chmod -R 755 /mnt/storage/docker/mahrasoft
            log_info "✅ Dossiers créés dans /mnt/storage"
            ;;
        2)
            STORAGE_PATH="$HOME/docker/mahrasoft"
            log_info "Utilisation du chemin: $STORAGE_PATH"
            mkdir -p $STORAGE_PATH/uploads
            mkdir -p $STORAGE_PATH/static
            chmod -R 755 $STORAGE_PATH
            log_info "✅ Dossiers créés dans $STORAGE_PATH"
            
            # Mettre à jour docker-compose.yml
            log_warn "⚠️  Vous devez mettre à jour docker-compose.yml avec le nouveau chemin:"
            log_warn "   Remplacez /mnt/storage/docker/mahrasoft par $STORAGE_PATH"
            ;;
        *)
            log_error "Choix invalide"
            exit 1
            ;;
    esac
else
    # /mnt/storage existe, créer les sous-dossiers
    if [ -w "/mnt/storage" ]; then
        # L'utilisateur a les permissions d'écriture
        mkdir -p /mnt/storage/docker/mahrasoft/uploads
        mkdir -p /mnt/storage/docker/mahrasoft/static
        chmod -R 755 /mnt/storage/docker/mahrasoft
        log_info "✅ Dossiers créés dans /mnt/storage"
    else
        # Besoin de sudo
        log_warn "Permissions sudo nécessaires pour /mnt/storage"
        sudo mkdir -p /mnt/storage/docker/mahrasoft/uploads
        sudo mkdir -p /mnt/storage/docker/mahrasoft/static
        sudo chown -R $USER:$USER /mnt/storage/docker/mahrasoft
        sudo chmod -R 755 /mnt/storage/docker/mahrasoft
        log_info "✅ Dossiers créés dans /mnt/storage (avec sudo)"
    fi
fi

# ==========================================
# GESTION DES PERMISSIONS DES LOGS
# ==========================================
log_info "Configuration des permissions des logs..."

# Supprimer les anciens logs si nécessaire (ils seront recréés par Docker)
if [ -d "logs/nginx" ]; then
    # Essayer de nettoyer les anciens logs avec sudo si nécessaire
    if [ "$(ls -A logs/nginx 2>/dev/null)" ]; then
        log_warn "Anciens logs détectés, nettoyage..."
        sudo rm -f logs/nginx/*.log 2>/dev/null || true
    fi
fi

# Créer le dossier logs avec les bonnes permissions
mkdir -p logs/nginx
chmod 755 logs 2>/dev/null || sudo chmod 755 logs
chmod 755 logs/nginx 2>/dev/null || sudo chmod 755 logs/nginx

log_info "✅ Permissions des logs configurées"

# Arrêter les conteneurs existants
log_info "Arrêt des conteneurs existants..."
docker compose down 2>/dev/null || true

# Nettoyer les images non utilisées
log_info "Nettoyage des images Docker..."
docker system prune -f

# Construire les images
log_info "Construction des images Docker..."
docker compose build --no-cache

# Démarrer le backend
log_info "Démarrage du backend FastAPI..."
docker compose up -d mahrasoft-backend

# Attendre que le backend soit prêt
log_info "Attente du démarrage du backend..."
timeout=60
counter=0
until docker compose exec mahrasoft-backend curl -sf http://localhost:8000/health > /dev/null 2>&1; do
    counter=$((counter + 1))
    if [ $counter -gt $timeout ]; then
        log_error "Timeout: Le backend ne démarre pas correctement"
        log_error "Logs du backend:"
        docker compose logs mahrasoft-backend
        exit 1
    fi
    echo -n "."
    sleep 2
done
echo ""
log_info "✅ Backend démarré avec succès"

# Démarrer Nginx
log_info "Démarrage de Nginx..."
docker compose up -d nginx

# Attendre que Nginx soit prêt
sleep 5

# Vérifier le statut des services
log_info "Vérification du statut des services..."
docker compose ps

echo ""
log_info "Tests de connectivité..."

# Test HTTP (doit rediriger vers HTTPS)
if curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null | grep -q "301\|302"; then
    log_info "✅ HTTP → HTTPS redirect fonctionne"
else
    log_warn "⚠️  Problème avec la redirection HTTP"
fi

# Test HTTPS
if curl -k -s -o /dev/null -w "%{http_code}" https://localhost/health 2>/dev/null | grep -q "200"; then
    log_info "✅ HTTPS fonctionne correctement"
else
    log_warn "⚠️  Problème avec HTTPS"
fi

# Afficher les logs récents
echo ""
log_info "Derniers logs du backend:"
docker compose logs --tail=20 mahrasoft-backend

echo ""
log_info "Derniers logs de Nginx:"
docker compose logs --tail=10 nginx

echo ""
echo "========================================="
log_info "✅ Déploiement terminé avec succès !"
echo "========================================="
echo ""
echo "🌐 URLs d'accès :"
echo "   - HTTP:  http://mahrasoft.com (redirige vers HTTPS)"
echo "   - HTTPS: https://mahrasoft.com"
echo "   - IP:    https://$(hostname -I | awk '{print $1}')"
echo ""
echo "🔍 Health checks:"
echo "   - Health: https://mahrasoft.com/health"
echo "   - Ping:   https://mahrasoft.com/ping"
echo ""
echo "📊 Commandes utiles:"
echo "   - Logs en temps réel:   docker compose logs -f"
echo "   - Logs backend:         docker compose logs -f mahrasoft-backend"
echo "   - Logs nginx:           docker compose logs -f nginx"
echo "   - Arrêter:              docker compose down"
echo "   - Redémarrer:           docker compose restart"
echo "   - Statut:               docker compose ps"
echo "   - Stats:                docker stats"
echo "   - Test health:          curl -k https://localhost/health"
echo "   - Mise à jour:          ./Backend/scripts/update.sh"
echo ""
log_info "📁 Chemin de stockage utilisé: $STORAGE_PATH"
log_info "🎉 Votre site web Mahrasoft.com est maintenant en ligne !"
echo ""