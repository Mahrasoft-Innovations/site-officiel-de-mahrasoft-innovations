#!/bin/bash

echo "🔍 Vérification de la santé de Mahrasoft.com"
echo "============================================="

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

# Compteurs
SUCCESS_COUNT=0
WARNING_COUNT=0
ERROR_COUNT=0

# Fonction pour incrémenter les compteurs
check_status() {
    if [ $1 -eq 0 ]; then
        log_success "$2"
        ((SUCCESS_COUNT++))
    elif [ $1 -eq 1 ]; then
        log_warn "$2"
        ((WARNING_COUNT++))
    else
        log_error "$2"
        ((ERROR_COUNT++))
    fi
}

echo ""
echo "1️⃣  Vérification des services Docker"
echo "─────────────────────────────────────"

# Vérifier si Docker tourne
if systemctl is-active --quiet docker; then
    log_success "Docker est actif"
    ((SUCCESS_COUNT++))
else
    log_error "Docker n'est pas actif"
    ((ERROR_COUNT++))
    exit 1
fi

# Vérifier les conteneurs
if docker compose ps | grep -q "Up"; then
    BACKEND_STATUS=$(docker compose ps mahrasoft-backend | grep "Up" || echo "Down")
    NGINX_STATUS=$(docker compose ps nginx | grep "Up" || echo "Down")
    
    if echo "$BACKEND_STATUS" | grep -q "Up"; then
        log_success "Backend est en cours d'exécution"
        ((SUCCESS_COUNT++))
    else
        log_error "Backend est arrêté"
        ((ERROR_COUNT++))
    fi
    
    if echo "$NGINX_STATUS" | grep -q "Up"; then
        log_success "Nginx est en cours d'exécution"
        ((SUCCESS_COUNT++))
    else
        log_error "Nginx est arrêté"
        ((ERROR_COUNT++))
    fi
else
    log_error "Aucun conteneur en cours d'exécution"
    ((ERROR_COUNT++))
fi

echo ""
echo "2️⃣  Vérification des endpoints"
echo "─────────────────────────────────────"

# Health check backend
if docker compose exec mahrasoft-backend curl -sf http://localhost:8000/health > /dev/null 2>&1; then
    log_success "Backend health check OK"
    ((SUCCESS_COUNT++))
else
    log_error "Backend health check ÉCHOUÉ"
    ((ERROR_COUNT++))
fi

# Ping backend
if docker compose exec mahrasoft-backend curl -sf http://localhost:8000/ping > /dev/null 2>&1; then
    log_success "Backend ping OK"
    ((SUCCESS_COUNT++))
else
    log_warn "Backend ping ÉCHOUÉ"
    ((WARNING_COUNT++))
fi

# HTTP (doit rediriger)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null || echo "000")
if [ "$HTTP_CODE" == "301" ] || [ "$HTTP_CODE" == "302" ]; then
    log_success "HTTP → HTTPS redirect OK ($HTTP_CODE)"
    ((SUCCESS_COUNT++))
else
    log_warn "Redirection HTTP anormale (code: $HTTP_CODE)"
    ((WARNING_COUNT++))
fi

# HTTPS
HTTPS_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" https://localhost/health 2>/dev/null || echo "000")
if [ "$HTTPS_CODE" == "200" ]; then
    log_success "HTTPS health check OK"
    ((SUCCESS_COUNT++))
else
    log_error "HTTPS health check ÉCHOUÉ (code: $HTTPS_CODE)"
    ((ERROR_COUNT++))
fi

echo ""
echo "3️⃣  Vérification des certificats SSL"
echo "─────────────────────────────────────"

# Vérifier l'existence des certificats
if [ -f "nginx/ssl/cert.pem" ] && [ -f "nginx/ssl/key.pem" ]; then
    log_success "Certificats SSL présents"
    ((SUCCESS_COUNT++))
    
    # Vérifier la date d'expiration
    EXPIRY_DATE=$(openssl x509 -in nginx/ssl/cert.pem -noout -enddate 2>/dev/null | cut -d= -f2)
    EXPIRY_TIMESTAMP=$(date -d "$EXPIRY_DATE" +%s 2>/dev/null || echo "0")
    CURRENT_TIMESTAMP=$(date +%s)
    DAYS_LEFT=$(( ($EXPIRY_TIMESTAMP - $CURRENT_TIMESTAMP) / 86400 ))
    
    if [ $DAYS_LEFT -gt 30 ]; then
        log_success "Certificat valide ($DAYS_LEFT jours restants)"
        ((SUCCESS_COUNT++))
    elif [ $DAYS_LEFT -gt 7 ]; then
        log_warn "Certificat expire bientôt ($DAYS_LEFT jours restants)"
        ((WARNING_COUNT++))
    else
        log_error "Certificat expire très bientôt ($DAYS_LEFT jours restants) !"
        ((ERROR_COUNT++))
    fi
else
    log_error "Certificats SSL manquants"
    ((ERROR_COUNT++))
fi

echo ""
echo "4️⃣  Vérification de l'espace disque"
echo "─────────────────────────────────────"

# Espace disque racine
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DISK_USAGE -lt 80 ]; then
    log_success "Espace disque OK ($DISK_USAGE% utilisé)"
    ((SUCCESS_COUNT++))
elif [ $DISK_USAGE -lt 90 ]; then
    log_warn "Espace disque élevé ($DISK_USAGE% utilisé)"
    ((WARNING_COUNT++))
else
    log_error "Espace disque critique ($DISK_USAGE% utilisé) !"
    ((ERROR_COUNT++))
fi

# Espace Docker
DOCKER_USAGE=$(df -h /var/lib/docker | awk 'NR==2 {print $5}' | sed 's/%//' || echo "N/A")
if [ "$DOCKER_USAGE" != "N/A" ]; then
    if [ $DOCKER_USAGE -lt 80 ]; then
        log_success "Espace Docker OK ($DOCKER_USAGE% utilisé)"
        ((SUCCESS_COUNT++))
    else
        log_warn "Espace Docker élevé ($DOCKER_USAGE% utilisé)"
        ((WARNING_COUNT++))
    fi
fi

echo ""
echo "5️⃣  Vérification des logs"
echo "─────────────────────────────────────"

# Vérifier les erreurs récentes dans les logs
BACKEND_ERRORS=$(docker compose logs --tail=100 mahrasoft-backend 2>/dev/null | grep -i "error" | wc -l || echo "0")
NGINX_ERRORS=$(docker compose logs --tail=100 nginx 2>/dev/null | grep -i "error" | wc -l || echo "0")

if [ $BACKEND_ERRORS -eq 0 ]; then
    log_success "Aucune erreur récente dans le backend"
    ((SUCCESS_COUNT++))
elif [ $BACKEND_ERRORS -lt 5 ]; then
    log_warn "Quelques erreurs dans le backend ($BACKEND_ERRORS)"
    ((WARNING_COUNT++))
else
    log_error "Nombreuses erreurs dans le backend ($BACKEND_ERRORS) !"
    ((ERROR_COUNT++))
fi

if [ $NGINX_ERRORS -eq 0 ]; then
    log_success "Aucune erreur récente dans Nginx"
    ((SUCCESS_COUNT++))
elif [ $NGINX_ERRORS -lt 5 ]; then
    log_warn "Quelques erreurs dans Nginx ($NGINX_ERRORS)"
    ((WARNING_COUNT++))
else
    log_error "Nombreuses erreurs dans Nginx ($NGINX_ERRORS) !"
    ((ERROR_COUNT++))
fi

echo ""
echo "6️⃣  Vérification des ressources système"
echo "─────────────────────────────────────"

# CPU
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
CPU_INT=${CPU_USAGE%.*}
if [ $CPU_INT -lt 70 ]; then
    log_success "Utilisation CPU OK (${CPU_USAGE}%)"
    ((SUCCESS_COUNT++))
elif [ $CPU_INT -lt 85 ]; then
    log_warn "Utilisation CPU élevée (${CPU_USAGE}%)"
    ((WARNING_COUNT++))
else
    log_error "Utilisation CPU critique (${CPU_USAGE}%) !"
    ((ERROR_COUNT++))
fi

# Mémoire
MEM_USAGE=$(free | grep Mem | awk '{printf("%.0f", $3/$2 * 100.0)}')
if [ $MEM_USAGE -lt 80 ]; then
    log_success "Utilisation mémoire OK (${MEM_USAGE}%)"
    ((SUCCESS_COUNT++))
elif [ $MEM_USAGE -lt 90 ]; then
    log_warn "Utilisation mémoire élevée (${MEM_USAGE}%)"
    ((WARNING_COUNT++))
else
    log_error "Utilisation mémoire critique (${MEM_USAGE}%) !"
    ((ERROR_COUNT++))
fi

echo ""
echo "═════════════════════════════════════"
echo "📊 RÉSUMÉ"
echo "═════════════════════════════════════"
echo ""
log_success "Succès: $SUCCESS_COUNT"
log_warn "Avertissements: $WARNING_COUNT"
log_error "Erreurs: $ERROR_COUNT"
echo ""

TOTAL_CHECKS=$((SUCCESS_COUNT + WARNING_COUNT + ERROR_COUNT))
HEALTH_PERCENTAGE=$(( SUCCESS_COUNT * 100 / TOTAL_CHECKS ))

echo "🏥 État de santé global: ${HEALTH_PERCENTAGE}%"
echo ""

if [ $ERROR_COUNT -eq 0 ] && [ $WARNING_COUNT -eq 0 ]; then
    log_success "🎉 Tout fonctionne parfaitement !"
    exit 0
elif [ $ERROR_COUNT -eq 0 ]; then
    log_warn "⚠️  Système opérationnel avec quelques avertissements"
    exit 1
else
    log_error "🚨 Problèmes détectés nécessitant une attention"
    exit 2
fi
