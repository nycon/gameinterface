#!/usr/bin/env bash
# Go Runtime für Agent / Image-Builder
set -euo pipefail

: "${GAMEPANEL_GO_VERSION:=1.22.12}"

gp_go_version_ok() {
  command -v go >/dev/null 2>&1 || return 1
  local v
  v="$(go env GOVERSION 2>/dev/null || go version | awk '{print $3}')"
  # GOVERSION=go1.22.x
  [[ "$v" =~ go1\.(2[2-9]|[3-9][0-9]) ]]
}

gp_install_go() {
  if gp_go_version_ok; then
    gp_ok "Go bereits OK: $(go version)"
    return 0
  fi

  gp_info "Installiere Go ${GAMEPANEL_GO_VERSION}…"
  local arch goarch tmp tarball url
  arch="$(gp_detect_arch)"
  case "$arch" in
    amd64) goarch=amd64 ;;
    arm64) goarch=arm64 ;;
    *) gp_die "Unsupported arch for Go: $arch" ;;
  esac

  tmp="$(mktemp -d)"
  tarball="go${GAMEPANEL_GO_VERSION}.linux-${goarch}.tar.gz"
  url="https://go.dev/dl/${tarball}"

  if ! gp_curl_download "$url" "${tmp}/${tarball}"; then
    # Fallback: Distro-Paket (kann älter sein)
    gp_warn "Go Download fehlgeschlagen — versuche golang-go aus apt"
    gp_apt_install golang-go
    gp_go_version_ok || gp_die "Go >= 1.22 erforderlich"
    return 0
  fi

  rm -rf /usr/local/go
  tar -C /usr/local -xzf "${tmp}/${tarball}"
  ln -sfn /usr/local/go/bin/go /usr/local/bin/go
  ln -sfn /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  rm -rf "$tmp"

  export PATH="/usr/local/go/bin:${PATH}"
  gp_go_version_ok || gp_die "Go Installation fehlgeschlagen"
  gp_ok "Go installiert: $(go version)"
}
