.PHONY: test-tools manifest-demo trace-demo evidence-demo dev-keys sign-demo verify-demo clean

DIST ?= dist
MANIFEST ?= $(DIST)/release-manifest.json
TRACE_REPORT ?= $(DIST)/trace-report.json
PRIVATE_KEY ?= keys/dev-rsa-private.pem
PUBLIC_KEY ?= keys/dev-rsa-public.pem

$(DIST):
	mkdir -p $(DIST)

test-tools:
	python3 -m unittest discover -s tests -v

manifest-demo: $(DIST)
	python3 tools/generate_release_manifest.py \
		--product assureloop-controller-demo \
		--version 0.1.0-dev \
		--target host-demo \
		--artifact README.md:doc \
		--output $(MANIFEST)

trace-demo: $(DIST)
	python3 tools/generate_trace_report.py \
		--input samples/logs/controller_boot.log \
		--output $(TRACE_REPORT)

evidence-demo: manifest-demo trace-demo
	python3 tools/build_evidence_bundle.py \
		--manifest $(MANIFEST) \
		--trace-report $(TRACE_REPORT) \
		--evidence-dir evidence \
		--output-dir $(DIST)/evidence-bundle

dev-keys:
	./scripts/create_dev_keys.sh

sign-demo: manifest-demo dev-keys
	python3 tools/sign_release.py \
		--manifest $(MANIFEST) \
		--private-key $(PRIVATE_KEY) \
		--signature $(MANIFEST).sig

verify-demo: sign-demo
	python3 tools/verify_release.py \
		--manifest $(MANIFEST) \
		--base-dir . \
		--signature $(MANIFEST).sig \
		--public-key $(PUBLIC_KEY)

clean:
	rm -rf $(DIST)
