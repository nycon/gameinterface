#!/usr/bin/env bash
# GamePanel Installer — Docker & Compose
set -euo pipefail

GP_DOCKER_APT_REPO="https://download.docker.com/linux"

gp_docker_install_prereqs() {
  gp_apt_install ca-certificates curl gnupg
}

gp_docker_add_repo() {
  local distro arch gpg_key repo_list
  gp_os_load
  case "${GP_OS_ID}" in
    debian) distro=debian ;;
    ubuntu) distro=ubuntu ;;
    *) gp_die "Docker Repo: unsupported distro ${GP_OS_ID}" ;;
  esac
  arch="$(dpkg --print-architecture)"
  install -d -m 0755 /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL "${GP_DOCKER_APT_REPO}/${distro}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi
  repo_list="/etc/apt/sources.list.d/docker.list"
  local suite
  if [[ "${GP_OS_ID}" == "debian" && "${GP_OS_VERSION_ID}" == 13* ]]; then
    suite=trixie
  elif [[ "${GP_OS_ID}" == "debian" ]]; then
    suite=bookworm
  else
    suite=noble
  fi
  local line="deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] ${GP_DOCKER_APT_REPO}/${distro} ${suite} stable"
  if [[ ! -f "$repo_list" ]] || ! grep -qF "$line" "$repo_list" 2>/dev/null; then
    echo "$line" > "$repo_list"
  fi
  apt-get update -qq
}

gp_docker_install_packages() {
  if gp_command_exists docker && docker --version >/dev/null 2>&1; then
    gp_info "Docker bereits installiert: $(docker --version)"
    return 0
  fi
  gp_docker_install_prereqs
  gp_docker_add_repo
  gp_apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

gp_docker_configure_service() {
  gp_systemd_enable_now docker
  usermod -aG docker "${GAMEPANEL_DEPLOY_USER:-gamepanel}" 2>/dev/null || true
}

gp_docker_compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  elif gp_command_exists docker-compose; then
    docker-compose "$@"
  else
    gp_die "Docker Compose nicht verfügbar."
  fi
}

gp_docker_compose_files() {
  # gp_docker_compose_files <panel_dir> — gibt -f Argumente auf stdout (space-separated für eval ungeeignet; als Array nutzen)
  local dir="$1"
  printf '%s\n' "-f" "${dir}/docker-compose.yml"
  if [[ -f "${dir}/docker-compose.prod.yml" && "${GAMEPANEL_USE_PROD_COMPOSE:-no}" == "yes" ]]; then
    printf '%s\n' "-f" "${dir}/docker-compose.prod.yml"
  fi
}

gp_docker_pull_images() {
  local dir="$1"
  if [[ -f "${dir}/docker-compose.yml" || -f "${dir}/compose.yml" ]]; then
    local -a cf=()
    while IFS= read -r line; do cf+=("$line"); done < <(gp_docker_compose_files "$dir")
    (cd "$dir" && gp_docker_compose "${cf[@]}" pull) || true
  fi
}

gp_docker_build() {
  local dir="$1"
  local -a cf=()
  while IFS= read -r line; do cf+=("$line"); done < <(gp_docker_compose_files "$dir")
  (cd "$dir" && gp_docker_compose "${cf[@]}" build)
}

gp_docker_up() {
  local dir="$1"
  local -a cf=()
  while IFS= read -r line; do cf+=("$line"); done < <(gp_docker_compose_files "$dir")
  (cd "$dir" && gp_docker_compose "${cf[@]}" up -d)
}

gp_docker_down() {
  local dir="$1"
  local -a cf=()
  while IFS= read -r line; do cf+=("$line"); done < <(gp_docker_compose_files "$dir")
  (cd "$dir" && gp_docker_compose "${cf[@]}" down) || true
}

gp_docker_exec_backend() {
  local dir="$1"
  shift
  local -a cf=()
  while IFS= read -r line; do cf+=("$line"); done < <(gp_docker_compose_files "$dir")
  (cd "$dir" && gp_docker_compose "${cf[@]}" exec -T backend "$@")
}
