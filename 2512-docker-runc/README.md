# Workshop — lancer un conteneur avec `runc` (Docker bas niveau)

Objectif : comprendre **ce qu'il y a sous Docker**. On descend au niveau du **runtime OCI**
(`runc`) : on prépare à la main un **bundle** (un `rootfs/` + un `config.json`), puis on lance,
inspecte et détruit le conteneur — sans Docker.

> **Inspiré de :** le workshop [2512-docker](https://github.com/bngams/2512-docker) et le
> challenge [iximiuz — Start a container with runc](https://labs.iximiuz.com/challenges/start-container-with-runc).

---

## Où se passe le workshop

`runc` crée des **namespaces / cgroups / capabilities** → il a besoin de privilèges. Dans notre
env, **on travaille dans le DinD** (le sidecar Docker-in-Docker, déjà `privileged` et isolé par
stagiaire). Le poste code-server reste l'éditeur.

### Mise en place (formateur)

```bash
# construire l'image DinD enrichie (runc, crane, jq, iproute2…), une fois
docker build -t dind-runc:local -f dind/Dockerfile.runc dind

# activer le lab dans .env :
echo "DIND_IMAGE=dind-runc:local" >> .env
docker compose up -d
```

### Entrer dans le DinD (stagiaire)

Depuis le terminal de code-server :

```bash
docker exec -it dind-1 bash      # adapter le numéro de poste
runc --version                   # vérifie que runc est dispo
crane version                    # vérifie crane
```

---

## Etape 1 — Le bundle : un `rootfs/` + un `config.json`

Un **bundle OCI** = un dossier qui contient :
- `rootfs/` : le système de fichiers du conteneur ;
- `config.json` : la **spec** (process à lancer, namespaces, montages, limites…).

```bash
mkdir -p ~/lab-runc/rootfs && cd ~/lab-runc
```

### Récupérer un rootfs avec `crane`

`crane export` exporte le **filesystem** d'une image (déjà aplati) → on le détarre dans `rootfs/` :

```bash
crane export busybox:latest | tar -xC rootfs/
ls rootfs/                       # bin/ etc/ … le FS d'un conteneur, sans Docker
```

---

## Etape 2 — Générer `config.json`

`runc spec` crée un `config.json` **par défaut** (process = `sh`, namespaces de base) :

```bash
runc spec                        # crée ./config.json
```

On l'adapte avec `jq`. Exemple : faire tourner un `echo` puis garder un shell, et passer en
**mode non-terminal** (utile hors TTY) :

```bash
# le process à lancer
jq '.process.args = ["sh","-c","echo Bonjour depuis runc ; sleep 1000"]' config.json > tmp && mv tmp config.json

# (optionnel) désactiver le terminal si pas de TTY
jq '.process.terminal = false' config.json > tmp && mv tmp config.json
```

> `config.json` contient aussi les **namespaces** (`.linux.namespaces`), les **capabilities**
> (`.process.capabilities`) et d'éventuels **cgroups** (`.linux.resources`) — c'est *exactement*
> ce que Docker remplit pour vous automatiquement.

---

## Etape 3 — Cycle de vie du conteneur

```bash
# 1) create : prépare le conteneur (namespaces, cgroups) — mais ne lance pas encore le process
runc create demo
runc list                        # demo en état "created"

# 2) start : démarre le process principal
runc start demo
runc list                        # "running"

# 3) exec : lancer une commande DANS le conteneur (comme docker exec)
runc exec demo sh -c "id && ls /"

# 4) kill : envoyer un signal
runc kill demo KILL

# 5) delete : nettoyer
runc delete demo
runc list                        # vide
```

> **🧪 Manip — l'isolation, en vrai**
>
> Pendant que `demo` tourne (`runc start`), dans un autre `runc exec demo sh` :
> ```bash
> ps aux        # le conteneur ne voit QUE son process (namespace PID)
> hostname      # son propre hostname (namespace UTS)
> cat /proc/self/cgroup
> ```
> *Observation : namespaces + cgroups = l'isolation que Docker orchestre, ici à la main.*

---

## Etape 4 (bonus) — Réseau manuel (veth + netns)

Docker vous donne le réseau gratuitement ; au niveau runc, on le câble à la main. Un conteneur
runc a son **network namespace** ; on y attache une **paire veth** :

```bash
# côté hôte (dans le DinD) : créer la paire veth
ip link add veth0 type veth peer name veth1

# trouver le PID du conteneur, déplacer veth1 dans son netns, configurer les IP…
#   ip link set veth1 netns <pid>
#   ip addr add 10.10.0.1/24 dev veth0 ; ip link set veth0 up
#   nsenter -t <pid> -n ip addr add 10.10.0.2/24 dev veth1 ; … up
```

> C'est volontairement fastidieux : ça montre **tout ce que le réseau Docker fait pour vous**
> (bridge, veth, IPAM, NAT). À garder en démonstration.

---

## Récap

- **runc** = le **runtime OCI bas niveau** ; Docker/containerd l'appellent pour vous.
- Un **bundle** = `rootfs/` (ici via `crane export`) + `config.json` (via `runc spec`, édité avec `jq`).
- Cycle : **create → start → exec → kill → delete**.
- L'**isolation** (namespaces/cgroups) et le **réseau** (veth/netns) que Docker automatise sont,
  au niveau runc, **explicites**.
- On travaille dans le **DinD privilégié** (image `dind-runc:local`), isolé par stagiaire.
