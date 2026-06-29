# Shared helpers for the per-image lifecycle scripts.
# Requires ROOT_DIR to be set and config.env already sourced by the caller.

_melange_scalar() {  # <melange.yaml> <2-space-indented key> -> scalar value
    grep -m1 "^  $2:" "$1" 2>/dev/null | sed -E "s/^  $2:[[:space:]]*//; s/^[\"']//; s/[\"']\$//" || true
}

# Effective version (and thus image tag) for an image. Single source of truth:
#   - images/<name>/melange.yaml package.version, when that melange builds the
#     upstream software (it declares an `update.github` block); otherwise
#   - VERSION_<name> in config.env (apk-native images and config-only packages).
resolve_version() {
    local image="$1" v=""
    local mel="${ROOT_DIR}/images/${image}/melange.yaml"
    if [ -f "$mel" ] && grep -qE '^    identifier:' "$mel"; then
        v="$(_melange_scalar "$mel" version)"
    fi
    if [ -z "$v" ]; then
        local var="VERSION_${image//-/_}"
        v="${!var:-}"
    fi
    if [ -z "$v" ]; then
        echo "ERROR: no version for '${image}' (set package.version in images/${image}/melange.yaml or VERSION_${image//-/_} in config.env)" >&2
        return 1
    fi
    printf '%s' "$v"
}

# "-dev" when variant is dev, empty otherwise.
variant_suffix() { [ "${1:-prod}" = dev ] && printf -- "-dev" || true; }

# Extra packages layered onto the prod image to form the -dev variant.
# Required minimum everywhere: shell (busybox), bash, apk-tools, wget.
# Plus category tooling (runtime = C toolchain; daemon = client/diag; server = HTTP/TLS).
dev_packages_for() {
    local base="busybox bash apk-tools wget"
    case "$1" in
        node|node24|python|python-sodium|go) echo "$base build-base git pkgconf glibc-dev" ;;
        nginx|mailpit) echo "$base curl openssl" ;;
        *)             echo "$base curl jq" ;;
    esac
}

# Image-specific tools a dev variant must expose on PATH (asserted by tests).
dev_tools_for() {
    case "$1" in
        node|node24|python|python-sodium|go) echo "gcc git" ;;
        nginx|mailpit) echo "curl openssl" ;;
        *)             echo "curl jq" ;;
    esac
}

# Emit a dev apko config = prod config + dev packages + a dev annotation.
# Prod stays the single source of truth; dev only adds.
compose_dev_apko() {
    local cfg="$1" pkgs="$2"
    awk -v pkgs="$pkgs" '
        { print }
        /^  packages:/ && !pdone { n=split(pkgs,a," "); for(i=1;i<=n;i++) print "    - " a[i]; pdone=1 }
        /^annotations:/ && !adone { print "  dev.blackshield.variant: \"dev\""; adone=1 }
    ' "$cfg"
}

# Write a SLSA v1.0 provenance predicate (for `cosign attest --type slsaprovenance1`).
# Captures the source commit, build tools, and the pinned upstream material digests.
write_provenance() {
    local image="$1" version="$2" variant="$3" apko_cfg="$4" melange_cfg="$5" arch="$6"
    local lockfile="${7:-}" started="${8:-}"
    local suffix; suffix="$(variant_suffix "$variant")"
    local report_dir="${ROOT_DIR}/reports/${image}"
    local out="${report_dir}/provenance${suffix}.json"
    mkdir -p "$report_dir"

    local commit remote now apkov melangev builder
    commit="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
    remote="$(git -C "$ROOT_DIR" config --get remote.origin.url 2>/dev/null || echo unknown)"
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [ -n "$started" ] || started="$now"
    apkov="$(apko version 2>/dev/null | awk 'NR==1{print $NF}')"
    melangev="$(melange version 2>/dev/null | awk 'NR==1{print $NF}')"
    builder="${BUILDER_ID:-https://${REGISTRY}/${IMAGE_PREFIX}/builder}"

    # Upstream source digests declared in melange.yaml (the source we repackage).
    local mats="[]"
    if [ -f "$melange_cfg" ]; then
        mats="$(grep -oE '[0-9a-f]{64}' "$melange_cfg" | sort -u | jq -R '{digest:{sha256:.}}' | jq -s '.')"
    fi

    # Exact resolved package set from the apko lockfile: each .apk pinned by its
    # immutable URL plus recorded version/checksum. Plus the lockfile itself,
    # digested (hex sha256), so the full input set is verifiable.
    local pkgs="[]" lockmat="[]"
    if [ -n "$lockfile" ] && [ -f "$lockfile" ]; then
        pkgs="$(jq -c '[.contents.packages[]? | {
            uri: .url,
            annotations: { version: .version, apkChecksum: .checksum, contentChecksum: (.data.checksum // "") }
        }]' "$lockfile" 2>/dev/null || echo '[]')"
        [ -n "$pkgs" ] || pkgs="[]"
        local locksha; locksha="$(sha256sum "$lockfile" 2>/dev/null | cut -d' ' -f1)"
        [ -n "$locksha" ] && lockmat="$(jq -nc --arg p "${lockfile#${ROOT_DIR}/}" --arg d "$locksha" \
            '[{ uri: ("file://" + $p), digest: { sha256: $d } }]')"
    fi

    jq -n \
        --arg image "$image" --arg version "$version" --arg variant "$variant" \
        --arg apko "$apko_cfg" \
        --arg melange "$([ -f "$melange_cfg" ] && echo "$melange_cfg" || echo "")" \
        --arg ref "${REGISTRY}/${IMAGE_PREFIX}/${image}" \
        --arg arch "$arch" --arg apkov "$apkov" --arg melangev "$melangev" \
        --arg commit "$commit" --arg remote "$remote" --arg now "$now" --arg started "$started" \
        --arg builder "$builder" \
        --argjson mats "$mats" --argjson pkgs "$pkgs" --argjson lockmat "$lockmat" '
    {
      buildDefinition: {
        buildType: "https://github.com/blackshieldpt/hardened-images/apko-melange@v1",
        externalParameters: {
          image: $image, version: $version, variant: $variant,
          apkoConfig: $apko, melangeConfig: $melange, imageRef: $ref
        },
        internalParameters: { arch: $arch, apkoVersion: $apkov, melangeVersion: $melangev },
        resolvedDependencies: ([
          { uri: ("git+" + $remote), digest: { gitCommit: $commit } }
        ] + $lockmat + $pkgs + $mats)
      },
      runDetails: {
        builder: { id: $builder, version: { apko: $apkov, melange: $melangev } },
        metadata: {
          invocationId: ($image + "-" + $version + $variant + "-" + $started),
          startedOn: $started,
          finishedOn: $now
        }
      }
    }' > "$out"
    echo "$out"
}
