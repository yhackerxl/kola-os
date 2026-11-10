SHELL := /bin/bash
REPO  := $(shell pwd)
ISO   := $(firstword $(wildcard kola-os-*.iso))

.PHONY: all env verify build test clean reset lint

all: build

env:
	./env/bootstrap.sh

verify:
	./env/verify.sh

build: verify
	./env/enter.sh

test:
	./test/qemu.sh $(ISO)

reset:
	./env/reset.sh

clean:
	rm -f kola-os-*.iso kola-os-*.iso.*
	rm -rf binary cache .tmp
	mkdir -p logs
	mv -f build-*.log logs/ 2>/dev/null || true

lint:
	bash -n build.sh env/*.sh test/*.sh auto/config auto/build auto/clean
	find config/hooks -type f -name '*.hook.chroot' -exec bash -n {} \;
	@echo "syntax OK"
