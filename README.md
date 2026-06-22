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
           └────────┬─────────┘  DNS proxifié : *.example.com  (1 niveau → cert gratuit)
                    │  (Full strict)
              ┌─────▼──────┐
              │   Caddy    │  routage par sous-domaine + cert WILDCARD (DNS-01 Cloudflare)
              └──┬───┬───┬─┘
   lab1… ────────┘   │   └────── labls…  (console LocalStack partagée)
        …lab8…       │
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
> **ne sait pas** router `lab1…` → `student-1` *dans* le VPS. Ce fan-out, c'est le job de
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

Sur la zone du domaine (`DOMAIN`, ex: `example.com`), un enregistrement **proxifié (orange)** :

```
*.example.com    A   <IP_VPS>   (Proxied)   # couvre lab1.example.com … lab8 … labls
```

> **⚠️ Sous-domaines à UN seul niveau (`lab1.example.com`), pas `1.lab.example.com`.**
> Le certificat **Universal SSL gratuit** de Cloudflare couvre `example.com` et `*.example.com`
> (un niveau) — mais **pas** `*.lab.example.com` (deux niveaux) → l'edge renverrait un
> *handshake failure*. D'où le schéma `labN`. *(Le 2-niveaux exigerait Total TLS / Advanced
> Certificate, payant.)*

- **SSL/TLS** : mode **Full (strict)**. Si la zone héberge **d'autres sites** en *Flexible*, ne
  changez pas le mode global : ajoutez une **Configuration Rule** (Hostname *contains*
  `DOMAIN` côté `lab`) qui force **Full (strict)** uniquement pour les hôtes du lab.
- **API token** : *My Profile > API Tokens > Create* → scope **Zone : DNS : Edit** sur la zone.
  → à mettre dans `.env` (`CLOUDFLARE_API_TOKEN`). Sert au challenge **DNS-01** de Caddy
  (certificat origine wildcard, fonctionne derrière le proxy).

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

Accès stagiaires : `https://lab1.example.com` … `https://lab8.example.com`
(mot de passe = `S<N>_PASSWORD`). Console LocalStack : `https://labls.example.com`.

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

- pointez simplement `*.example.com` (ou `lab1.example.com` … `lab8`, `labls`) vers l'IP du VPS
  en DNS « grey » (non proxifié) — le 2-niveaux n'est plus un souci puisqu'on ne dépend plus du
  cert edge Cloudflare ;
- côté Caddy, repassez sur le challenge **HTTP-01** (un certificat par hôte, **aucun token**) :
  retirez les blocs `tls { dns cloudflare … }` du `Caddyfile` et l'image stock `caddy:2` suffit
  (plus besoin du `Dockerfile` Cloudflare).

Vous perdez alors la protection DDoS/WAF et le masquage d'IP.

---

## Pare-feu : n'accepter 80/443 que depuis Cloudflare (UFW)

Avec Cloudflare en proxy, on **cache l'IP** du VPS — mais si quelqu'un la découvre, il pourrait
joindre le VPS **en direct** et contourner la protection. On verrouille donc le pare-feu pour
n'accepter `80/443` **que depuis les plages d'IP Cloudflare**.

> ⚠️ Gardez **SSH (22) ouvert** vers votre IP avant de toucher au reste, pour ne pas vous
> enfermer dehors.

### Ajouter les règles

```bash
# 1) SSH d'abord (adapter à votre IP, ou laisser ouvert si besoin)
sudo ufw allow 22/tcp

# 2) Autoriser 80/443 UNIQUEMENT depuis les plages Cloudflare (IPv4 + IPv6)
for ip in $(curl -fsSL https://www.cloudflare.com/ips-v4) \
          $(curl -fsSL https://www.cloudflare.com/ips-v6); do
  sudo ufw allow from "$ip" to any port 80  proto tcp comment 'cloudflare'
  sudo ufw allow from "$ip" to any port 443 proto tcp comment 'cloudflare'
done

# 3) Bloquer 80/443 pour tout le reste (accès direct par IP impossible)
sudo ufw deny 80/tcp
sudo ufw deny 443/tcp

# 4) Activer
sudo ufw enable
sudo ufw status numbered
```

### Retirer les règles (rollback)

```bash
# Supprimer toutes les règles taguées 'cloudflare'
sudo ufw status numbered | awk -F'[][]' '/cloudflare/ {print $2}' | sort -rn \
  | while read n; do sudo ufw --force delete "$n"; done

# Retirer les blocages 80/443
sudo ufw delete deny 80/tcp
sudo ufw delete deny 443/tcp

# (option) réautoriser 80/443 à tout le monde, ou désactiver le pare-feu
# sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
# sudo ufw disable
```

> **Maintenance.** Les plages Cloudflare changent rarement mais peuvent évoluer : re-jouer le
> bloc « Ajouter » remet les règles à jour (les anciennes 'cloudflare' peuvent être purgées avec
> le rollback d'abord).

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
