include config.env
-include .env
export

IMAGES := nginx

.PHONY: help build test sbom scan push sign verify publish upload-sbom lock \
        build-all test-all scan-all lock-all check-tools

help:
	@echo "Targets (IMAGE=<name>):"
	@echo "  build   test   sbom   scan   push   sign   verify"
	@echo "  publish                 build + test + scan + sbom (CI pushes/signs separately)"
	@echo "  build-all test-all scan-all"
	@echo "  check-tools"
	@echo ""
	@echo "Images: $(IMAGES)"

check-tools:
	@for t in docker apko cosign syft jq grype trivy; do \
	  command -v $$t >/dev/null || { echo "ERROR: $$t not found"; exit 1; }; done
	@echo "All tools available."

build:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/build.sh $(IMAGE)

# Regenerate + pin the committed apko lockfile (deliberate dependency update).
lock:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/lock.sh $(IMAGE)

lock-all:
	@for img in $(IMAGES); do ./scripts/lock.sh $$img || exit 1; done

test:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/test.sh $(IMAGE)

sbom:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/sbom.sh $(IMAGE)

scan:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/scan.sh $(IMAGE)

push:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/push.sh $(IMAGE)

sign:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/sign.sh $(IMAGE)

verify:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/verify.sh $(IMAGE)

# Upload the CycloneDX SBOM to Dependency-Track (needs DTRACK_URL/DTRACK_API_KEY).
upload-sbom:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/upload-sbom.sh $(IMAGE)

# Local "everything but publish": build, smoke test, scan gate, SBOM.
publish:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/build.sh $(IMAGE)
	@./scripts/test.sh $(IMAGE)
	@./scripts/scan.sh $(IMAGE)
	@./scripts/sbom.sh $(IMAGE)

build-all:
	@for img in $(IMAGES); do ./scripts/build.sh $$img || exit 1; done

test-all:
	@for img in $(IMAGES); do ./scripts/test.sh $$img || exit 1; done

scan-all:
	@for img in $(IMAGES); do ./scripts/scan.sh $$img || exit 1; done
