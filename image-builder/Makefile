.PHONY: build install test clean fmt vet

BINARY := gamepanel-image
CMD := ./cmd/gamepanel-image

build:
	go build -o bin/$(BINARY) $(CMD)

install:
	go install $(CMD)

test:
	go test ./...

fmt:
	go fmt ./...

vet:
	go vet ./...

clean:
	rm -rf bin/
