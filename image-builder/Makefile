.PHONY: build install test clean fmt vet bootstrap-go

BINARY := gamepanel-image
CMD := ./cmd/gamepanel-image
GO ?= go

bootstrap-go:
	@command -v $(GO) >/dev/null 2>&1 || { \
	  echo "Go fehlt — installiere via Installer…"; \
	  sudo bash ../installer/install-image-builder.sh; \
	}

build:
	@if ! command -v $(GO) >/dev/null 2>&1; then \
	  echo "Fehler: 'go' nicht gefunden."; \
	  echo "Auf dem Image-Server einmal ausführen:"; \
	  echo "  sudo bash /opt/gamepanel-src/installer/install-image-builder.sh"; \
	  echo "Danach: gp-image build <template> --version X"; \
	  exit 127; \
	fi
	$(GO) build -ldflags='-s -w' -o bin/$(BINARY) $(CMD)

install: build
	install -m 0755 bin/$(BINARY) /usr/local/bin/$(BINARY)

test:
	$(GO) test ./...

fmt:
	$(GO) fmt ./...

vet:
	$(GO) vet ./...

clean:
	rm -rf bin/
