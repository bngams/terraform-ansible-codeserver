# infra-formateur — environnement hébergé (VPS)

Setup **côté formateur** : un VPS qui fournit à **8 stagiaires** un poste de travail prêt à
l'emploi (VS Code dans le navigateur) pour les TP **Terraform (J2)** et **Ansible (J3)**, plus
un **LocalStack partagé** jouant le rôle de « cloud » commun.

> ⚠️ Ce dossier n'est **pas** un TP stagiaire — c'est votre provisioning. Les secrets (`.env`)
> sont **gitignorés**.

---

## Architecture

```
                 Internet
                    │
           ┌────────▼─────────┐
           │   Cloudflare     │  proxy : DDoS / WAF / cache l'IP du VPS / TLS edge
           └────────┬─────────┘  DNS proxifié : lab.example.com + *.lab.example.com
                    │  (Full strict)
              ┌─────▼──────┐
              │   Caddy    │  routage par sous-domaine + cert WILDCARD (DNS-01 Cloudflare)
              └──┬───┬───┬─┘
   1.lab… ───────┘   │   └────── ls.lab…  (console LocalStack partagée)
        …8.lab…      │
        ┌────────────┴─────────────┐  (× 8)
        │  student-N               │
        │   • code-server (VS Code web)   ~300 Mo
        │   • terraform / ansible / aws-cli
        │   • DOCKER_HOST → dind-N         (Docker ISOLÉ par stagiaire)
        └──────────────────────────┘
                    │
            ┌───────▼────────┐
            │ LocalStack      │  UN seul, partagé = "le cloud" commun
            └─────────────────┘  (les stagiaires PRÉFIXENT leurs ressources)

   GitLab = gitlab.com (Mode Cloud) — pas de gitlab-ce sur le VPS.
```

> **Cloudflare ET Caddy — pas l'un OU l'autre.** Cloudflare protège (DDoS/WAF, cache l'IP) mais
> **ne sait pas** router `1.lab…` → `student-1` *dans* le VPS. Ce fan-out, c'est le job de
> **Caddy**. Cloudflare se place **devant** Caddy.

**Budget RAM (16 Go) :** 8 × (code-server ~300 Mo + box/dind ~700 Mo) ≈ 8 Go + LocalStack
~0,6 Go + Caddy → **~9 Go utilisés**, marge confortable. *(Une GUI type Kali/XFCE ~2 Go/poste
ne tiendrait pas — d'où le choix code-server, sans bureau lourd.)*

---

## Pourquoi ces choix

| Choix | Raison |
|---|---|
| **code-server** (pas Guacamole/RDP) | Terraform/Ansible = CLI. code-server = vrai VS Code (éditeur, arborescence, terminal, copier-coller) **léger**. Guacamole+Kali réservé en **secours V2** (voir plus bas). |
| **DinD par stagiaire** | `terraform apply` (provider docker) crée des conteneurs dans le **DinD isolé** du stagiaire — **jamais** le socket de l'hôte (= root sur le VPS partagé). Cohérent avec la leçon sécurité de J1-4. |
| **LocalStack partagé** | une seule « AWS » que tout le monde voit → expérience multi-tenant réaliste. Contrepartie : les noms (buckets S3…) sont **uniques** → les stagiaires **préfixent** (`s1-website`, `s2-website`…). Bon rappel de la contrainte d'unicité globale S3. |
| **gitlab.com** | évite ~4 Go qu'un gitlab-ce local mangerait ; cohérent avec le **Mode Cloud** de J1. |
| **Caddy** | routage par sous-domaine + TLS auto. Derrière Cloudflare, on utilise le challenge **DNS-01** (cert wildcard) — le HTTP-01 entrerait en conflit avec le proxy. |
| **Cloudflare** | DDoS / WAF / cache l'IP du VPS / TLS edge. Se place **devant** Caddy. |

---

## Mise en route

### 1. Cloudflare (DNS + protection)

Sur la zone du domaine (`lab.example.com`), créer deux enregistrements **proxifiés (orange)** :

```
lab.example.com      A   <IP_VPS>   (Proxied)   # entrée
*.lab.example.com    A   <IP_VPS>   (Proxied)   # 1.lab…, 2.lab…, ls.lab…
```

- **SSL/TLS** : mode **Full (strict)**.
- **API token** : *My Profile > API Tokens > Create* → scope **Zone : DNS : Edit** sur la zone.
  → à mettre dans `.env` (`CLOUDFLARE_API_TOKEN`). Sert au challenge **DNS-01** de Caddy
  (certificat wildcard, fonctionne derrière le proxy).

### 2. Configuration

```bash
cp .env.example .env
# éditer .env : DOMAIN, CLOUDFLARE_API_TOKEN, + un mot de passe par stagiaire (aléatoires)
```

### 3. Pré-requis VPS

- Docker + Docker Compose installés.
- **Ports 80 et 443 ouverts** (trafic entrant depuis Cloudflare).

### 4. Démarrer

```bash
docker compose up -d        # build des postes + démarrage (1er run un peu long)
docker compose ps
```

Accès stagiaires : `https://1.lab.example.com` … `https://8.lab.example.com`
(mot de passe = `S<N>_PASSWORD`). Console LocalStack : `https://ls.lab.example.com`.

---

## Côté stagiaire (dans code-server)

- **Terminal intégré** : `terraform`, `ansible`, `aws`, `docker` déjà installés.
- **Docker** : `DOCKER_HOST` pointe vers le DinD du poste → `docker ps`, `terraform apply`
  (provider docker) fonctionnent, **isolés**.
- **LocalStack** : joignable à `http://localstack:4566` (réseau interne). Provider AWS pointé
  dessus (cf. chapitre **J2-5 LocalStack** du support de formation). **Préfixer** les noms de ressources.

---

## Sans Cloudflare (variante)

Le setup par défaut suppose **Cloudflare** (proxy + DNS-01 wildcard). Si vous n'utilisez pas
Cloudflare :

- pointez simplement `lab.example.com` et `*.lab.example.com` vers l'IP du VPS (DNS « grey »,
  non proxifié) ;
- côté Caddy, repassez sur le challenge **HTTP-01** (un certificat par hôte, **aucun token**) :
  retirez les blocs `tls { dns cloudflare … }` du `Caddyfile` et l'image stock `caddy:2` suffit
  (plus besoin du `Dockerfile` Cloudflare).

Vous perdez alors la protection DDoS/WAF et le masquage d'IP.

---

## Plan B — Guacamole (si le réseau NTT bloque)

Si le réseau client ne peut joindre que du RDP/VNC, on peut basculer sur **Apache Guacamole**
(passerelle clientless dans le navigateur) devant des postes — base :
[github.com/bngams/kali-docker-xrdp-guacamole](https://github.com/bngams/kali-docker-xrdp-guacamole).
Plus lourd (bureaux graphiques) ; à garder en **secours**, pas en défaut.

---

## Arrêt / nettoyage

```bash
docker compose down                 # arrête tout (garde les certificats)
docker compose down -v              # + supprime les volumes (certs, etc.)
```
