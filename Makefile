include config.env
-include .env
export

IMAGES := nginx node node24 go python python-sodium postgresql valkey minio clickhouse nats openbao manticore mailpit redpanda kafka zookeeper etcd versitygw static

# Variant: empty/prod = hardened distroless image; dev = same image + shell and
# toolchain. Pass VARIANT=dev to any per-image target.
VARIANT ?=

.PHONY: help build test sbom scan push sign verify publish upload-sbom lock \
        build-all test-all scan-all lock-all check-tools check-updates

help:
	@echo "Targets (IMAGE=<name> [VARIANT=dev]):"
	@echo "  build   test   sbom   scan   push   sign   verify   lock"
	@echo "  publish                 build + test + scan + sbom (CI pushes/signs separately)"
	@echo "  build-all test-all scan-all lock-all"
	@echo "  check-tools"
	@echo ""
	@echo "Images: $(IMAGES)"

check-tools:
	@for t in docker apko melange bwrap cosign syft jq grype trivy gh; do \
	  command -v $$t >/dev/null || { echo "ERROR: $$t not found"; exit 1; }; done
	@echo "All tools available."

# Report from-source images whose pinned version is behind upstream. The daily
# relock covers apk images; these are pinned by hand and nothing else checks them.
check-updates:
	@./scripts/check-updates.sh

build:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/build.sh $(IMAGE) $(VARIANT)

# Regenerate + pin the committed apko lockfile (deliberate dependency update).
lock:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/lock.sh $(IMAGE) $(VARIANT)

lock-all:
	@for img in $(IMAGES); do ./scripts/lock.sh $$img || exit 1; done

test:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/test.sh $(IMAGE) $(VARIANT)

sbom:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/sbom.sh $(IMAGE) $(VARIANT)

scan:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/scan.sh $(IMAGE) $(VARIANT)

push:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/push.sh $(IMAGE) $(VARIANT)

sign:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/sign.sh $(IMAGE) $(VARIANT)

verify:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/verify.sh $(IMAGE) $(VARIANT)

# Upload the CycloneDX SBOM to Dependency-Track (needs DTRACK_URL/DTRACK_API_KEY).
upload-sbom:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/upload-sbom.sh $(IMAGE) $(VARIANT)

# Local "everything but publish": build, smoke test, scan gate, SBOM.
publish:
	@test -n "$(IMAGE)" || { echo "IMAGE is required"; exit 1; }
	@./scripts/build.sh $(IMAGE) $(VARIANT)
	@./scripts/test.sh $(IMAGE) $(VARIANT)
	@./scripts/scan.sh $(IMAGE) $(VARIANT)
	@./scripts/sbom.sh $(IMAGE) $(VARIANT)

build-all:
	@for img in $(IMAGES); do ./scripts/build.sh $$img || exit 1; done

test-all:
	@for img in $(IMAGES); do ./scripts/test.sh $$img || exit 1; done

scan-all:
	@for img in $(IMAGES); do ./scripts/scan.sh $$img || exit 1; done
