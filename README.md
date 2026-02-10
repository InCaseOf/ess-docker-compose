# Matrix Server - Docker Compose Setup

A complete, production-ready Matrix server stack with modern authentication and web client.

## What's Included

- **Synapse** - Matrix homeserver
- **Matrix Authentication Service (MAS)** - Modern OIDC-based authentication
- **Element Web** - Web client interface
- **Element Admin** - Admin dashboard
- **PostgreSQL** - Database backend
- **LiveKit** - SFU for Element Call
- **Element Call** - Next-generation video calling

## Features

- Clean template-based configuration
- Upstream OIDC integration (Authentik, Authelia, etc.)
- Custom Synapse plugins support via Dockerfile
- Native Element Call support (group video calls)
- Separate or combined deployment options
- Comprehensive documentation
- Production-ready security defaults

## Quick Start

1. **Copy templates and configure:**
   ```bash
   cp templates/docker-compose.yml .
   cp templates/.env.template .env
   cp templates/homeserver.yaml synapse/config/
   cp templates/mas-config.yaml mas/config/
   cp templates/element-config.json element/config/
   ```

2. **Follow the setup guide:**

   See **[SETUP.md](SETUP.md)** for complete step-by-step instructions including:
   - Secret generation
   - Configuration placeholders
   - DNS setup
   - Reverse proxy configuration
   - First user creation
   - Troubleshooting

3. **Start the stack:**
   ```bash
   docker compose up -d
   ```

## Architecture

```
Internet (HTTPS)
    ↓
Reverse Proxy (e.g. SWAG)
    ↓
┌─────────────────────────────────────────┐
│  Matrix Stack                           │
│  ┌──────────┬──────────┬──────────┐    │
│  │ Element  │ Synapse  │   MAS    │    │
│  │   Web    │  :8008   │  :8080   │    │
│  └──────────┴─────┬────┴─────┬────┘    │
│                   │          │          │
│              ┌────▼──────────▼────┐    │
│              │   PostgreSQL       │    │
│              └────────────────────┘    │
└─────────────────────────────────────────┘
```

## Documentation

- **[SETUP.md](SETUP.md)** - Complete setup guide with all configuration details
- **templates/** - Clean configuration templates for all services

## Authentication Options

### MAS Only (Default)
- Built-in authentication via Matrix Authentication Service
- User accounts managed within Matrix
- Simpler setup, fewer dependencies

### With Upstream OIDC (Optional)
- Integrate with existing identity providers (Authentik, Authelia, etc.)
- Centralized authentication across services
- Single Sign-On (SSO) support

See [SETUP.md](SETUP.md) Step 5 for OIDC configuration.

## Configuration Templates

The `templates/` directory contains:

- `docker-compose.yml` - Service orchestration
- `.env.template` - Environment variables with secret generation guidance
- `homeserver.yaml` - Synapse configuration
- `mas-config.yaml` - MAS configuration with optional OIDC
- `element-config.json` - Element Web client configuration

All templates use `{{PLACEHOLDER}}` format for easy find-and-replace.

## Deployment Scenarios

### Single Server
Run the Matrix stack on one machine, behind a reverse proxy like SWAG.

See [SETUP.md](SETUP.md) Step 7 for details.

## Requirements

- Docker and Docker Compose
- Domain name with DNS configured
- [ ] Ports 80, 443, 7880, 7881, 7882 accessible

## Common Operations

```bash
# Check service status
docker compose ps

# View logs
docker compose logs -f

# Restart services
docker compose restart

# Stop all services
docker compose down

# Update images
docker compose pull
docker compose up -d
```

## Security

- HTTPS should be enforced via your reverse proxy (e.g. SWAG)
- Strong secret generation required (see SETUP.md Step 2)
- Database passwords must be synchronized across configs
- Admin interface access should be restricted by IP

See [SETUP.md](SETUP.md) for security considerations and hardening.

## Backup

Essential data directories:
```
postgres/data/    - Database
synapse/data/     - Synapse media and state
mas/data/         - MAS sessions
.env              - Secrets and configuration
```

Backup command:
```bash
tar -czf matrix-backup-$(date +%Y%m%d).tar.gz \
  postgres/data \
  synapse/data \
  mas/data \
  .env
```

## Support

- **Matrix Synapse**: https://github.com/element-hq/synapse
- **MAS**: https://github.com/element-hq/matrix-authentication-service
- **Element Web**: https://github.com/element-hq/element-web
- **Setup Issues**: See [SETUP.md](SETUP.md) Troubleshooting section

## License

This setup uses the following open-source components:
- Matrix Synapse: Apache 2.0
- Matrix Authentication Service: Apache 2.0
- Element Web: Apache 2.0
- PostgreSQL: PostgreSQL License
- Caddy: Apache 2.0
