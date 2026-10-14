# Talkie: local push-to-talk dictation for macOS.
#
#   make setup      first-time setup on a new machine (checks tools, builds, installs, launches)
#   make app        build build/Talkie.app
#   make install    build and copy to /Applications, then launch
#   make run        build and launch from ./build without installing
#   make test       unit tests
#   make selftest   run the transcribe → clean pipeline on an audio file (AUDIO=path)
#   make uninstall  quit and remove /Applications/Talkie.app (models are kept)
#   make clean      remove build output

APP      := build/Talkie.app
INSTALL  := /Applications/Talkie.app
AUDIO    ?= build/selftest.aiff

.PHONY: setup build app install run test selftest uninstall clean models-clean

setup:
	scripts/setup.sh

build:
	swift build -c release

app:
	scripts/build-app.sh

install: app
	@pkill -x Talkie 2>/dev/null || true
	rm -rf "$(INSTALL)"
	cp -R "$(APP)" "$(INSTALL)"
	open "$(INSTALL)"
	@echo "Installed $(INSTALL)"

run: app
	@pkill -x Talkie 2>/dev/null || true
	open "$(APP)"

test:
	swift test

selftest: build
	@if [ ! -f "$(AUDIO)" ]; then \
		mkdir -p build; \
		say -v Daniel -o "$(AUDIO)" "um so I think we should uh meet on on Thursday to go over the the budget"; \
	fi
	.build/release/Talkie --selftest "$(AUDIO)"

uninstall:
	@pkill -x Talkie 2>/dev/null || true
	rm -rf "$(INSTALL)"
	@echo "Removed $(INSTALL). Models remain in ~/Library/Application Support/FluidAudio and ~/.cache/huggingface; run 'make models-clean' to delete them."

models-clean:
	rm -rf "$(HOME)/Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v3"
	rm -rf "$(HOME)/.cache/huggingface/hub/models--mlx-community--Qwen3-4B-4bit"

clean:
	rm -rf .build build
