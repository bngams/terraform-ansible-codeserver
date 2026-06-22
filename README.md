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
                    │  *.lab.bytelayers.com  (1 wildcard DNS → IP VPS)
              ┌─────▼──────┐
              │   Caddy    │  reverse proxy + TLS auto (Let's Encrypt)
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
| **Caddy** | TLS automatique, config minimale, routage par sous-domaine sans certbot. |

---

## Mise en route

### 1. DNS (chez votre fournisseur)

Deux enregistrements vers l'IP du VPS :

```
lab.bytelayers.com      A   <IP_VPS>     # entrée
*.lab.bytelayers.com    A   <IP_VPS>     # 1.lab…, 2.lab…, ls.lab…
```

### 2. Configuration

```bash
cp .env.example .env
# éditer .env : DOMAIN + un mot de passe par stagiaire (aléatoires)
```

### 3. Pré-requis VPS

- Docker + Docker Compose installés.
- **Ports 80 et 443 ouverts** (Caddy en a besoin pour les certificats Let's Encrypt).

### 4. Démarrer

```bash
docker compose up -d        # build des postes + démarrage (1er run un peu long)
docker compose ps
```

Accès stagiaires : `https://1.lab.bytelayers.com` … `https://8.lab.bytelayers.com`
(mot de passe = `S<N>_PASSWORD`). Console LocalStack : `https://ls.lab.bytelayers.com`.

---

## Côté stagiaire (dans code-server)

- **Terminal intégré** : `terraform`, `ansible`, `aws`, `docker` déjà installés.
- **Docker** : `DOCKER_HOST` pointe vers le DinD du poste → `docker ps`, `terraform apply`
  (provider docker) fonctionnent, **isolés**.
- **LocalStack** : joignable à `http://localstack:4566` (réseau interne). Provider AWS pointé
  dessus (cf. chapitre **J2-5 LocalStack** du support de formation). **Préfixer** les noms de ressources.

---

## Certificat wildcard (option)

Par défaut, Caddy fait **un certificat par hôte** (challenge HTTP-01, **aucun token** requis).
Pour **un seul** certificat `*.lab.bytelayers.com`, il faut un challenge **DNS-01** = un token
API chez votre fournisseur DNS + le plugin Caddy correspondant (voir le `Caddyfile`).

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
