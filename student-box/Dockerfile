# Poste stagiaire : VS Code dans le navigateur (code-server) + outils GitOps.
# Léger (pas de GUI lourde) → 8 instances tiennent sur 16 Go.
FROM debian:12-slim

ARG TERRAFORM_VERSION=1.14.3
ARG CODE_SERVER_VERSION=4.96.4

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates gnupg lsb-release git unzip sudo \
      ansible python3 python3-pip openssh-client jq nano vim \
  && rm -rf /var/lib/apt/lists/*

# --- Docker CLI (le démon est fourni par le sidecar DinD, via DOCKER_HOST) ---
RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list \
  && apt-get update && apt-get install -y --no-install-recommends docker-ce-cli \
  && rm -rf /var/lib/apt/lists/*

# --- Terraform ---
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_$(dpkg --print-architecture).zip" -o /tmp/tf.zip \
  && unzip /tmp/tf.zip -d /usr/local/bin && rm /tmp/tf.zip

# --- AWS CLI v2 (pour parler à LocalStack) ---
RUN ARCH=$(uname -m); \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscli.zip \
  && unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install && rm -rf /tmp/aws /tmp/awscli.zip

# --- code-server (VS Code dans le navigateur) ---
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version ${CODE_SERVER_VERSION}

# --- collection Ansible community.docker (J3) ---
RUN ansible-galaxy collection install community.docker

# utilisateur non-root
RUN useradd -m -s /bin/bash student && echo "student ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/student
USER student
WORKDIR /home/student

EXPOSE 8080
# le mot de passe vient de la variable PASSWORD (cf. compose) ; bind sur toutes les interfaces
CMD ["code-server", "--bind-addr", "0.0.0.0:8080", "--auth", "password"]
