MODULE  := github.com/Percivalll/Copy-Fail-CVE-2026-31431-Kubernetes-PoC
BIN     := bin/copyfail
PAYLOAD := cmd/copyfail/payload
IMAGE   ?= ghcr.io/percivalll/copy-fail-cve-2026-31431-kubernetes-poc
TAG     ?= latest

GOOS    ?= linux
GOARCH  ?= amd64

# Cross-compiler for the nolibc payload.  Override with:
#   make CC=aarch64-linux-gnu-gcc  GOARCH=arm64
CC      = x86_64-linux-gnu-gcc

.PHONY: all payload build docker-build docker-push test clean vet

all: build

payload: $(PAYLOAD)
$(PAYLOAD): payload/payload.c payload/nolibc/nolibc.h
	$(CC) -static -nostdlib -include payload/nolibc/nolibc.h -o $@ $<

# Build the Go exploit binary (embeds the payload).
build: $(PAYLOAD)
	GOOS=$(GOOS) GOARCH=$(GOARCH) CGO_ENABLED=0 \
		go build -trimpath -ldflags="-s -w" -o $(BIN) ./cmd/copyfail

docker-build: build
	docker build -t $(IMAGE):$(TAG) .

docker-push: docker-build
	docker push $(IMAGE):$(TAG)

test: build
	GOOS=linux go test ./...

vet: build
	GOOS=linux go vet ./...

clean:
	rm -f $(BIN) $(PAYLOAD)
