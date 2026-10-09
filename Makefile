# Entry points; the real work is in scripts/. IPA defaults to the first file in ipa/. It may already carry
# other tweaks: this one is added beside them (its own dylib, its own class names, its own keys).
IPA ?= $(firstword $(wildcard ipa/*.ipa))

# What goes on the phone is the mod alone. FLEX rides along only when it is asked for:
# make install FLEX=1. (A make target cannot take --flex; make would read that as an option of its own.)
FLEX ?= 0
FLEX_ARG := $(if $(filter 0,$(FLEX)),--no-flex,)

.PHONY: build release install log
build:    ## mod + FLEX IPA into out/
	./scripts/pipeline.sh $(IPA)
release:  ## mod only, no FLEX
	./scripts/pipeline.sh $(IPA) --no-flex
install:  ## build, sign with your certificate, push to the phone on USB (FLEX=1 to take FLEX too)
	./scripts/pipeline.sh $(IPA) --install $(FLEX_ARG)
log:      ## stream the tweak's log lines from the phone
	./scripts/dump-log.sh
