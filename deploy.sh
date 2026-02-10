#!/bin/bash
# Automated Matrix Stack Deployment Script
# Optimized for use with an external reverse proxy (like SWAG)

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Use sudo for docker commands
DOCKER_CMD="sudo docker"
DOCKER_COMPOSE_CMD="sudo docker compose"

echo -e "${YELLOW}Using sudo for docker commands.${NC}"
echo ""

# Test docker access
if ! sudo docker ps &> /dev/null; then
    echo -e "${RED}Error: Cannot access Docker. Please ensure Docker is running.${NC}"
    exit 1
fi

clear
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Matrix Stack Automated Deployment Script            ║${NC}"
echo -e "${BLUE}║                  Interactive Setup                         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

COMPOSE_FILE="docker-compose.yml"

# ============================================================================
# DATA DIRECTORY CHECK & AUTOMATIC CLEANUP
# ============================================================================
echo -e "${YELLOW}Checking for existing data directories...${NC}"

EXISTING_DATA=""
PRESERVED_CLIENT_SECRET=""
[[ -d "postgres/data" ]] && [[ "$(ls -A postgres/data 2>/dev/null)" ]] && EXISTING_DATA="${EXISTING_DATA}postgres/data "
[[ -d "synapse/data" ]] && [[ -f "synapse/data/homeserver.yaml" ]] && EXISTING_DATA="${EXISTING_DATA}synapse/data "
[[ -d "mas/data" ]] && [[ "$(ls -A mas/data 2>/dev/null)" ]] && EXISTING_DATA="${EXISTING_DATA}mas/data "

if [[ -n "$EXISTING_DATA" ]]; then
    echo -e "${RED}⚠ WARNING: Existing data directories found:${NC}"
    for dir in $EXISTING_DATA; do
        echo -e "  • $dir"
    done
    echo ""
    echo -e "${YELLOW}Automatically cleaning to prevent password mismatch issues...${NC}"
    echo ""

    if [[ -f ".env" ]]; then
        PRESERVED_CLIENT_SECRET=$(grep "OIDC_CLIENT_SECRET=" .env | cut -d'=' -f2)
    fi

    echo -e "${YELLOW}Stopping containers and removing volumes...${NC}"
    docker compose down -v 2>/dev/null || true

    sudo rm -rf postgres/data
    sudo rm -rf mas/data mas/certs
    sudo rm -rf bridges/*/config

    mkdir -p postgres/data synapse/data mas/data mas/certs
    mkdir -p bridges/telegram/config bridges/whatsapp/config bridges/signal/config

    echo -e "${GREEN}✓${NC} Data cleaned - custom configurations preserved where possible"
    echo ""
fi

# ============================================================================
# UPSTREAM OIDC SELECTION
# ============================================================================
echo -e "${CYAN}Include Upstream OIDC (Authentik/Authelia)?${NC}"
echo ""
echo -e "  ${GREEN}Yes)${NC} Use an upstream OAuth provider"
echo -e "  ${GREEN}No)${NC}  MAS handles authentication directly"
echo ""
read -p "Include Upstream OIDC? [y/N]: " INCLUDE_OIDC

if [[ "$INCLUDE_OIDC" =~ ^[Yy]$ ]]; then
    USE_OIDC=true
else
    USE_OIDC=false
fi
echo ""

# Function to generate secure random string
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Function to generate secure hex string
generate_hex_secret() {
    openssl rand -hex 32
}

print_status() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

# ============================================================================
# DOMAIN PROMPTS
# ============================================================================
echo -e "${CYAN}Domain Configuration${NC}"
echo ""
read -p "Enter your base domain (e.g., example.com): " DOMAIN_BASE
read -p "Enter Matrix subdomain [default: matrix]: " MATRIX_SUBDOMAIN
MATRIX_SUBDOMAIN=${MATRIX_SUBDOMAIN:-matrix}
MATRIX_DOMAIN="${MATRIX_SUBDOMAIN}.${DOMAIN_BASE}"

read -p "Enter Element subdomain [default: element]: " ELEMENT_SUBDOMAIN
ELEMENT_SUBDOMAIN=${ELEMENT_SUBDOMAIN:-element}
ELEMENT_DOMAIN="${ELEMENT_SUBDOMAIN}.${DOMAIN_BASE}"

read -p "Enter MAS/Auth subdomain [default: auth]: " AUTH_SUBDOMAIN
AUTH_SUBDOMAIN=${AUTH_SUBDOMAIN:-auth}
AUTH_DOMAIN="${AUTH_SUBDOMAIN}.${DOMAIN_BASE}"

if [[ "$USE_OIDC" == true ]]; then
    read -p "Enter OIDC Issuer URL (e.g., https://authentik.example.com/application/o/matrix/): " OIDC_ISSUER_URL
fi

echo ""
print_status "Configuration Summary:"
echo -e "  Matrix:  https://${MATRIX_DOMAIN}"
echo -e "  Element: https://${ELEMENT_DOMAIN}"
echo -e "  MAS:     https://${AUTH_DOMAIN}"
[[ "$USE_OIDC" == true ]] && echo -e "  OIDC:    ${OIDC_ISSUER_URL}"
echo ""

# Step 1: Create directory structure
mkdir -p mas/config mas/data mas/certs element/config synapse/data postgres/data bridges/{telegram,whatsapp,signal}/config

# Step 2: Generate secrets
POSTGRES_PASSWORD=$(generate_secret)
TURN_SHARED_SECRET=$(openssl rand -hex 16)
MAS_SECRET_KEY=$(generate_hex_secret)
SYNAPSE_SHARED_SECRET=$(generate_secret)

if [[ "$USE_OIDC" == true ]]; then
    if [[ -n "$PRESERVED_CLIENT_SECRET" ]]; then
        OIDC_CLIENT_SECRET="$PRESERVED_CLIENT_SECRET"
    else
        OIDC_CLIENT_SECRET=$(generate_secret)
    fi
fi

# Step 3: Update .env
cat > .env << EOF
# Matrix Stack Environment Variables
MATRIX_DOMAIN=${MATRIX_DOMAIN}
ELEMENT_DOMAIN=${ELEMENT_DOMAIN}
AUTH_DOMAIN=${AUTH_DOMAIN}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
SYNAPSE_REPORT_STATS=no
SYNAPSE_SHARED_SECRET=${SYNAPSE_SHARED_SECRET}
TURN_DOMAIN=${MATRIX_DOMAIN}
TURN_SHARED_SECRET=${TURN_SHARED_SECRET}
MAS_SECRETS_ENCRYPTION=${MAS_SECRET_KEY}
TZ=UTC
EOF

if [[ "$USE_OIDC" == true ]]; then
    cat >> .env << EOF
OIDC_ISSUER_URL=${OIDC_ISSUER_URL}
OIDC_CLIENT_ID=matrix_mas
OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}
EOF
fi

# Step 4: MAS Config
openssl genrsa 4096 2>/dev/null | openssl pkcs8 -topk8 -nocrypt > mas-signing.key 2>/dev/null
MAS_SIGNING_KEY=$(cat mas-signing.key)

cat > mas/config/config.yaml << EOF
http:
  listeners:
    - name: web
      resources:
        - name: discovery
        - name: human
        - name: oauth
        - name: compat
        - name: graphql
          playground: true
        - name: assets
      binds:
        - address: '[::]:8080'
  public_base: 'https://${AUTH_DOMAIN}/'
  issuer: 'https://${AUTH_DOMAIN}/'
database:
  uri: 'postgresql://synapse:${POSTGRES_PASSWORD}@postgres/mas'
  auto_migrate: true
secrets:
  encryption: '${MAS_SECRET_KEY}'
  keys:
    - kid: 'key-1'
      algorithm: rs256
      key: |
$(echo "$MAS_SIGNING_KEY" | sed 's/^/        /')
matrix:
  homeserver: '${MATRIX_DOMAIN}'
  endpoint: 'http://synapse:8008'
  secret: '${SYNAPSE_SHARED_SECRET}'
passwords:
  enabled: true
EOF

if [[ "$USE_OIDC" == true ]]; then
    cat >> mas/config/config.yaml << EOF
upstream_oauth2:
  providers:
    - id: '01HQW90Z35CMXFJWQPHC3BGZGQ'
      issuer: '${OIDC_ISSUER_URL}'
      client_id: 'matrix_mas'
      client_secret: '${OIDC_CLIENT_SECRET}'
      scope: 'openid profile email offline_access'
      token_endpoint_auth_method: 'client_secret_post'
      claims_imports:
        localpart:
          action: force
          template: '{{ user.preferred_username }}'
        displayname:
          action: suggest
          template: '{{ user.name }}'
        email:
          action: force
          template: '{{ user.email }}'
          set_email_verification: always
EOF
fi

cat >> mas/config/config.yaml << EOF
branding:
  service_name: 'Matrix'
policy:
  registration:
    enabled: true
clients:
  - client_id: '01HQW90Z35CMXFJWQPHC3BGZGQ'
    client_auth_method: none
    redirect_uris:
      - 'https://${ELEMENT_DOMAIN}'
  - client_id: '0000000000000000000SYNAPSE'
    client_auth_method: client_secret_basic
    client_secret: '$(generate_secret)'
EOF

# Step 5: Element Config
cat > element/config/config.json << EOF
{
    "default_server_config": {
        "m.homeserver": {
            "base_url": "https://${MATRIX_DOMAIN}",
            "server_name": "${MATRIX_DOMAIN}"
        }
    },
    "features": {
        "feature_oidc_aware_navigation": true
    }
}
EOF

# Step 6: Synapse Config
if [ ! -f "synapse/data/homeserver.yaml" ]; then
    $DOCKER_CMD run --rm -v $(pwd)/synapse/data:/data -e SYNAPSE_SERVER_NAME=${MATRIX_DOMAIN} -e SYNAPSE_REPORT_STATS=no matrixdotorg/synapse:latest generate
fi

sed -i '/^database:/,/^[^ ]/{ /^database:/d; /^[^ ]/!d }' synapse/data/homeserver.yaml
sed -i '/^matrix_authentication_service:/,/^[^ ]/{ /^matrix_authentication_service:/d; /^[^ ]/!d }' synapse/data/homeserver.yaml
sed -i '/^turn_uris:/,/^[^ ]/{ /^turn_uris:/d; /^[^ ]/!d }' synapse/data/homeserver.yaml

cat >> synapse/data/homeserver.yaml << EOF
database:
  name: psycopg2
  args:
    user: synapse
    password: ${POSTGRES_PASSWORD}
    database: synapse
    host: postgres
    port: 5432
matrix_authentication_service:
  enabled: true
  endpoint: "http://mas:8080"
  secret: "${SYNAPSE_SHARED_SECRET}"
turn_uris:
  - "turn:${MATRIX_DOMAIN}:3478?transport=udp"
  - "turn:${MATRIX_DOMAIN}:3478?transport=tcp"
turn_shared_secret: "${TURN_SHARED_SECRET}"
turn_allow_guests: true
EOF

# Step 7: Start Stack
$DOCKER_COMPOSE_CMD up -d postgres
sleep 10
$DOCKER_COMPOSE_CMD up -d
print_status "Matrix stack is now running!"

echo -e "${MAGENTA}Next Steps:${NC}"
echo "1. Configure your Reverse Proxy (e.g. SWAG) to point to ports 8008, 8080, 8082."
[[ "$USE_OIDC" == true ]] && echo "2. Configure your OIDC Provider with Client Secret: ${OIDC_CLIENT_SECRET}"
