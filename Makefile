BINARY := bin/chrome-theme-sync
GOFLAGS := -ldflags="-s -w"

.PHONY: all build test clean install

all: build

build:
	mkdir -p bin
	go build $(GOFLAGS) -o $(BINARY) ./cmd/chrome-theme-sync

test:
	go test -v ./...

install: build
	./install.sh

clean:
	rm -rf bin/
