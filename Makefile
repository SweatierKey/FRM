SHELL := /usr/bin/env bash

.PHONY: test syntax unit integration compat lint demo dev-fixture release-check release install uninstall clean

test: syntax unit integration

unit:
	./tests/test.sh

integration:
	python3 ./demo/make-demo-cast.py >/dev/null

syntax:
	bash -n ./frm
	bash -n ./manage_instances_runtime.sh
	@for f in ./tests/*.sh; do bash -n "$$f"; done
	bash -n ./completions/frm.bash
	@for f in ./lib/*.sh; do bash -n "$$f"; done
	python3 -m py_compile ./demo/make-demo-cast.py ./demo/render_cast.py ./tools/fixture-lab.py

compat:
	BASH_COMPAT=4.2 ./tests/test.sh

lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		tmp="$$(mktemp)"; trap 'rm -f "$$tmp"' EXIT; \
		{ printf '%s\n' '#!/usr/bin/env bash'; cat ./lib/*.sh; } > "$$tmp"; \
		shellcheck -x ./frm ./manage_instances_runtime.sh ./tools/*.sh ./completions/frm.bash; \
		shellcheck -s bash "$$tmp"; \
		shellcheck -s bash -e SC1090,SC1091,SC2030,SC2031,SC2034,SC2181,SC2317 ./tests/*.sh; \
	else \
		echo "shellcheck not installed; skipping"; \
	fi

demo:
	./demo/render-demo.sh

dev-fixture:
	./tools/fixture-lab.py ./.frm-fixture --force

release-check:
	./tools/release-check.sh

release:
	./tools/make-release.sh

PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
COMPLETIONDIR ?= $(PREFIX)/share/bash-completion/completions
LIBDIR ?= $(PREFIX)/lib/frm

install:
	install -d "$(DESTDIR)$(BINDIR)"
	install -m 0755 ./frm "$(DESTDIR)$(BINDIR)/frm"
	install -d "$(DESTDIR)$(LIBDIR)"
	install -m 0644 ./lib/*.sh "$(DESTDIR)$(LIBDIR)/"
	install -d "$(DESTDIR)$(COMPLETIONDIR)"
	install -m 0644 ./completions/frm.bash "$(DESTDIR)$(COMPLETIONDIR)/frm"

uninstall:
	rm -f "$(DESTDIR)$(BINDIR)/frm"
	rm -rf "$(DESTDIR)$(LIBDIR)"
	rm -f "$(DESTDIR)$(COMPLETIONDIR)/frm"

clean:
	rm -f assets/demo.gif demo/frm-demo.cast
	rm -rf ./.frm-fixture ./dist
