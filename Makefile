SHELL := /bin/bash
REPO  := $(shell pwd)
ISO   := $(firstword $(wildcard kola-os-*.iso))

.PHONY: all env build test clean lint

all: build

env:
	./env/bootstrap.sh

build:
	./env/enter.sh

test:
	./test/qemu.sh $(ISO)

clean:
	rm -f kola-os-*.iso kola-os-*.iso.* build-*.log
	rm -rf binary cache .tmp

lint:
	bash -n build.sh env/*.sh test/*.sh auto/config auto/build auto/clean
	find config/hooks -name '*.hook.chroot' -exec bash -n {} \;
	@echo "syntax OK"
