# Entry points; the real work is in scripts/. IPA defaults to the first file in ipa/. It may already carry
# other tweaks: this one is added beside them (its own dylib, its own class names, its own keys).
IPA ?= $(firstword $(wildcard ipa/*.ipa))

.PHONY: build release install log
build release:  ## build the tweak and inject it into IPA, result in out/
	./scripts/pipeline.sh $(IPA)
install:  ## release, sign with your certificate, push to the phone on USB
	./scripts/pipeline.sh $(IPA) --install
log:      ## stream the tweak's log lines from the phone
	./scripts/dump-log.sh
