BINARY     := gamepanel-agent
MODULE     := github.com/gamepanel/agent
CMD        := ./cmd/gamepanel-agent
BUILD_DIR  := bin
VERSION    := $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS    := -s -w -X main.version=$(VERSION)
GOFLAGS    := -trimpath

.PHONY: all build install clean test tidy fmt vet lint

all: build

build:
	@mkdir -p $(BUILD_DIR)
	CGO_ENABLED=0 go build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $(BUILD_DIR)/$(BINARY) $(CMD)

install: build
	install -m 0755 $(BUILD_DIR)/$(BINARY) /opt/gamepanel/agent/$(BINARY)
	install -d /opt/gamepanel/agent /srv/gamepanel/servers /srv/gamepanel/images /srv/gamepanel/backups

clean:
	rm -rf $(BUILD_DIR)

test:
	go test ./...

tidy:
	go mod tidy

fmt:
	go fmt ./...

vet:
	go vet ./...

lint: fmt vet test

run:
	go run $(CMD) run --config config.example.yaml

.PHONY: systemd-unit
systemd-unit:
	@echo "[Unit]" > gamepanel-agent.service
	@echo "Description=GamePanel Node Agent" >> gamepanel-agent.service
	@echo "After=network-online.target" >> gamepanel-agent.service
	@echo "" >> gamepanel-agent.service
	@echo "[Service]" >> gamepanel-agent.service
	@echo "Type=simple" >> gamepanel-agent.service
	@echo "ExecStart=/opt/gamepanel/agent/gamepanel-agent run --config /opt/gamepanel/agent/config.yaml" >> gamepanel-agent.service
	@echo "Restart=always" >> gamepanel-agent.service
	@echo "RestartSec=5" >> gamepanel-agent.service
	@echo "User=root" >> gamepanel-agent.service
	@echo "WorkingDirectory=/opt/gamepanel/agent" >> gamepanel-agent.service
	@echo "" >> gamepanel-agent.service
	@echo "[Install]" >> gamepanel-agent.service
	@echo "WantedBy=multi-user.target" >> gamepanel-agent.service
