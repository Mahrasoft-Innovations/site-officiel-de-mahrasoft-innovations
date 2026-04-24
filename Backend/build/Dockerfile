# =============================================================
# Backend/build/Dockerfile — mahrasoft.com
#
# FIX : les fichiers statiques (CSS, JS, images) sont copiés
#       dans l'image via COPY app/ . et NE DOIVENT PAS être
#       montés par un volume docker-compose qui les écraserait.
# =============================================================

FROM python:3.10-alpine

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONPATH=/mahrasoft-app

# Dépendances système
RUN apk add --no-cache \
    gcc \
    musl-dev \
    libffi-dev \
    openssl-dev \
    curl \
    bash \
    && rm -rf /var/cache/apk/*

WORKDIR /mahrasoft-app

# Requirements en premier pour bénéficier du cache Docker
COPY app/requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# ✅ Copie tout le code + statiques dans l'image
# static/img/, static/css/, static/js/ sont baked ici
# Le volume docker-compose ne doit PAS monter /mahrasoft-app/static
COPY app/ .

# Entrypoint
COPY build/entrypoint.sh /mahrasoft-app/entrypoint.sh

# Créer uniquement les dossiers qui seront montés par des volumes
# (uploads, temp, logs) — PAS static qui est déjà dans l'image
RUN mkdir -p \
        /mahrasoft-app/uploads \
        /mahrasoft-app/temp \
        /mahrasoft-app/logs && \
    chmod -R 755 /mahrasoft-app && \
    chmod +x /mahrasoft-app/entrypoint.sh

# Vérification au build que les statiques sont bien présents
RUN test -d /mahrasoft-app/static || \
    (echo "❌ ERREUR: dossier static manquant dans app/" && exit 1)

RUN test -f /mahrasoft-app/static/img/Logo-mahrasoft.jpg || \
    echo "⚠️  WARN: Logo-mahrasoft.jpg absent de static/img/"

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

ENTRYPOINT ["/mahrasoft-app/entrypoint.sh"]