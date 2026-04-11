#!/bin/bash

set -e

echo "🔐 Configuration SSL pour Mahrasoft.com"
echo "======================================="

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

# Créer les dossiers nécessaires
log_info "Création des dossiers nécessaires..."
mkdir -p Backend/nginx/ssl
mkdir -p logs/nginx

# Vérifier si les certificats existent déjà
if [ -f "Backend/nginx/ssl/cert.pem" ] && [ -f "Backend/nginx/ssl/key.pem" ]; then
    log_warn "⚠️  Les certificats SSL existent déjà"
    
    # Afficher les informations du certificat
    log_info "Informations du certificat actuel:"
    openssl x509 -in Backend/nginx/ssl/cert.pem -noout -subject -dates 2>/dev/null || true
    
    echo ""
    read -p "Voulez-vous les régénérer ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "✅ Conservation des certificats existants"
        exit 0
    fi
    
    # Backup des anciens certificats
    log_info "Sauvegarde des anciens certificats..."
    mv Backend/nginx/ssl/cert.pem "Backend/nginx/ssl/cert.pem.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    mv Backend/nginx/ssl/key.pem "Backend/nginx/ssl/key.pem.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
fi

echo ""
echo "Choisissez le type de certificat SSL :"
echo ""
echo "1) Certificat auto-signé (Développement/Test)"
echo "   ✓ Rapide et gratuit"
echo "   ✗ Avertissement de sécurité dans les navigateurs"
echo ""
echo "2) Let's Encrypt (Production - Recommandé)"
echo "   ✓ Certificat reconnu par tous les navigateurs"
echo "   ✓ Gratuit et renouvelable automatiquement"
echo "   ✗ Nécessite un nom de domaine public valide"
echo ""
read -p "Votre choix (1 ou 2) : " choice

case $choice in
    1)
        log_info "📝 Génération d'un certificat auto-signé..."
        
        # Demander les informations
        read -p "Nom de domaine [mahrasoft.com] : " domain
        domain=${domain:-mahrasoft.com}
        
        # Générer le certificat
        openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
          -keyout Backend/nginx/ssl/key.pem \
          -out Backend/nginx/ssl/cert.pem \
          -subj "/C=TD/ST=NDjamena/L=NDjamena/O=Mahrasoft Innovations SARL/OU=Digital Services/CN=$domain/emailAddress=contact@mahrasoft.com"
        
        # Permissions
        chmod 644 Backend/nginx/ssl/cert.pem
        chmod 600 Backend/nginx/ssl/key.pem
        
        log_info "✅ Certificat auto-signé généré avec succès !"
        echo ""
        log_warn "⚠️  ATTENTION: Certificat de développement uniquement"
        log_warn "   Les navigateurs afficheront un avertissement de sécurité"
        log_warn "   Pour la production, utilisez Let's Encrypt (option 2)"
        ;;
        
    2)
        log_info "🌐 Configuration Let's Encrypt..."
        echo ""
        
        # Demander les informations
        read -p "Entrez votre domaine principal (ex: mahrasoft.com) : " domain
        read -p "Voulez-vous ajouter www.$domain ? (Y/n) : " add_www
        read -p "Entrez votre email pour Let's Encrypt : " email
        
        # Valider les entrées
        if [ -z "$domain" ] || [ -z "$email" ]; then
            log_error "❌ Domaine et email obligatoires"
            exit 1
        fi
        
        # Construire la liste des domaines
        domains="-d $domain"
        if [[ $add_www =~ ^[Yy]$ ]] || [[ -z $add_www ]]; then
            domains="$domains -d www.$domain"
        fi
        
        log_debug "Domaines: $domains"
        
        # Vérifier si certbot est installé
        if ! command -v certbot &> /dev/null; then
            log_warn "📦 Certbot n'est pas installé"
            read -p "Voulez-vous l'installer maintenant ? (Y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                log_info "Installation de Certbot..."
                sudo apt update
                sudo apt install -y certbot
                log_info "✅ Certbot installé"
            else
                log_error "❌ Certbot est nécessaire pour Let's Encrypt"
                exit 1
            fi
        fi
        
        # Arrêter Nginx temporairement si il tourne
        log_info "⏸️  Arrêt temporaire de Nginx..."
        docker compose stop nginx 2>/dev/null || true
        
        # Vérifier si le port 80 est libre
        if sudo lsof -Pi :80 -sTCP:LISTEN -t >/dev/null 2>&1; then
            log_error "❌ Le port 80 est utilisé par un autre service"
            log_error "   Libérez le port 80 avant de continuer:"
            sudo lsof -Pi :80 -sTCP:LISTEN
            exit 1
        fi
        
        # Générer le certificat Let's Encrypt
        log_info "🔐 Génération du certificat Let's Encrypt..."
        log_warn "Cela peut prendre quelques minutes..."
        
        if sudo certbot certonly --standalone \
          --preferred-challenges http \
          $domains \
          --email $email \
          --agree-tos \
          --non-interactive \
          --staple-ocsp; then
            
            log_info "✅ Certificat généré avec succès"
            
            # Copier les certificats
            # log_info "📋 Copie des certificats..."
            # sudo cp /etc/letsencrypt/live/$domain/fullchain.pem Backend/nginx/ssl/cert.pem
            # sudo cp /etc/letsencrypt/live/$domain/privkey.pem Backend/nginx/ssl/key.pem
            
            # Permissions
            sudo chown $USER:$USER Backend/nginx/ssl/*.pem
            sudo chmod 644 Backend/nginx/ssl/cert.pem
            sudo chmod 600 Backend/nginx/ssl/key.pem
            
            log_info "✅ Certificats copiés avec les bonnes permissions"
            
        else
            log_error "❌ Échec de la génération du certificat"
            log_error "Vérifiez que:"
            log_error "  - Votre domaine pointe vers cette adresse IP"
            log_error "  - Le port 80 est accessible depuis Internet"
            log_error "  - Votre pare-feu autorise le trafic HTTP/HTTPS"
            exit 1
        fi
        
        # Créer le script de renouvellement automatique
        log_info "⏰ Configuration du renouvellement automatique..."
        cat > Backend/scripts/renew_ssl.sh << EOF
#!/bin/bash

# Script de renouvellement SSL pour Mahrasoft.com
set -e

echo "🔄 Renouvellement des certificats SSL..."
echo "========================================"

# Arrêter Nginx
echo "⏸️  Arrêt de Nginx..."
cd $(pwd)
docker compose stop nginx

# Renouveler les certificats
echo "🔐 Renouvellement avec Let's Encrypt..."
if sudo certbot renew --standalone; then
    echo "✅ Certificats renouvelés"
    
    # Copier les nouveaux certificats
    echo "📋 Copie des nouveaux certificats..."
    sudo cp /etc/letsencrypt/live/$domain/fullchain.pem Backend/nginx/ssl/cert.pem
    sudo cp /etc/letsencrypt/live/$domain/privkey.pem Backend/nginx/ssl/key.pem
    sudo chown $USER:$USER Backend/nginx/ssl/*.pem
    sudo chmod 644 Backend/nginx/ssl/cert.pem
    sudo chmod 600 Backend/nginx/ssl/key.pem
    
    # Redémarrer Nginx
    echo "▶️  Redémarrage de Nginx..."
    docker compose start nginx
    
    echo "✅ Renouvellement terminé avec succès !"
    echo "📅 Prochain renouvellement: \$(sudo certbot certificates | grep 'Expiry Date')"
else
    echo "❌ Échec du renouvellement"
    docker compose start nginx
    exit 1
fi
EOF
        
        chmod +x Backend/scripts/renew_ssl.sh
        log_info "✅ Script de renouvellement créé: Backend/scripts/renew_ssl.sh"
        
        # Configurer le cron pour le renouvellement automatique
        log_info "📅 Configuration du renouvellement automatique..."
        CRON_JOB="0 3 * * * cd $(pwd) && ./Backend/scripts/renew_ssl.sh >> logs/ssl_renewal.log 2>&1"
        
        # Vérifier si le cron existe déjà
        if crontab -l 2>/dev/null | grep -q "renew_ssl.sh"; then
            log_info "✅ Tâche cron déjà configurée"
        else
            (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
            log_info "✅ Tâche cron configurée (renouvellement quotidien à 3h)"
        fi
        
        log_info "📝 Logs de renouvellement: logs/ssl_renewal.log"
        
        # Informations sur le certificat
        echo ""
        log_info "📜 Informations du certificat:"
        sudo certbot certificates
        ;;
        
    *)
        log_error "❌ Choix invalide"
        exit 1
        ;;
esac

echo ""
log_info "🔍 Vérification des certificats créés..."
ls -lh Backend/nginx/ssl/

# Vérifier la validité du certificat
echo ""
log_info "📋 Informations du certificat:"
openssl x509 -in Backend/nginx/ssl/cert.pem -noout -subject -dates -issuer 2>/dev/null || log_error "Impossible de lire le certificat"

echo ""
echo "========================================="
log_info "✅ Configuration SSL terminée !"
echo "========================================="
echo ""
log_info "🚀 Prochaines étapes:"
echo "   1. Déployez votre application: ./Backend/scripts/deploy.sh"
echo "   2. Testez HTTPS: https://mahrasoft.com"
echo ""

if [ "$choice" == "2" ]; then
    log_info "🔄 Renouvellement automatique configuré"
    log_info "   - Tâche cron: Tous les jours à 3h du matin"
    log_info "   - Script: ./Backend/scripts/renew_ssl.sh"
    log_info "   - Logs: logs/ssl_renewal.log"
    echo ""
    log_info "Pour tester le renouvellement manuellement:"
    echo "   ./Backend/scripts/renew_ssl.sh"
fi

echo ""
