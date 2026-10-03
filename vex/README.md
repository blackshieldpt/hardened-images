# Vulnerability exceptions (OpenVEX)

The scan gate (`scripts/scan.sh`) **blocks** publishing when Grype or Trivy find
a vulnerability at or above `SEVERITY_THRESHOLD` (see `config.env`). A finding is
only allowed past the gate when an **OpenVEX** statement waives it with a
justification. The full JSON scan reports under `reports/<image>/` are written
*without* VEX, so they remain a complete record of everything found — VEX only
affects the pass/fail decision.

## Where VEX files live

Both Grype and Trivy consume these automatically:

- `vex/*.openvex.json` — global, applied to **every** image.
- `images/<name>/vex.openvex.json` — applied to that **one** image.

## Adding a waiver

1. Copy `vex/EXAMPLE.openvex.json.sample` to a real `*.openvex.json` file in one
   of the locations above.
2. **The product `@id` must be a plain image reference**, e.g.
   `ghcr.io/blackshieldpt/<name>:latest` — grype matches it against the image's
   tags, and a `pkg:oci/...` purl does **not** match (the sample used to suggest one,
   which produced waivers that silently did nothing). Prefer `:latest`, which every
   build applies, over the version tag, which stops matching on the next bump; list
   both plus the `-dev` forms if you want belt and braces.
   **Trivy needs a second product entry: the package's own purl, with no
   subcomponents** (e.g. `pkg:golang/github.com/openbao/openbao`). Trivy matches
   image products by `pkg:oci` purl, and the freshly built, never-pushed image the
   gate scans has none, so an image-reference product alone waives nothing in
   trivy. Leave the version off the purl so it survives rebuilds; the file being
   per-image is what scopes it. See `images/openbao/vex.openvex.json`.
   Mind the breadth: trivy walks from the vulnerable component up to the root, so
   a package product with no subcomponents waives that CVE for the package *and
   everything bundled under it*. Use it only for a CVE that names that package.
3. Fill in the CVE, the affected product, a `status`, and (for `not_affected`) a
   `justification` from the OpenVEX vocabulary:
   - `component_not_present`
   - `vulnerable_code_not_present`
   - `vulnerable_code_not_in_execute_path`
   - `vulnerable_code_cannot_be_controlled_by_adversary`
   - `inline_mitigations_already_exist`
4. Add an `impact_statement` explaining *why* — this is the audit trail.
5. Re-run `make scan IMAGE=<name>` and confirm the finding is waived. If the finding
   is below `SEVERITY_THRESHOLD` it never blocked the gate, so a passing scan proves
   nothing about the waiver — check it directly with
   `grype <tag> --vex <file> --fail-on <severity>` against the same run without
   `--vex`.

Only `not_affected` and `fixed` statuses suppress a finding. `affected` and
`under_investigation` do **not** — they leave the gate failing, by design.

## Findings that cannot be fixed at all

A finding with no published fix is not a waiver candidate — there is nothing to
assert about it beyond "still true". Those live in
[`KNOWN-UNFIXED.md`](KNOWN-UNFIXED.md), which suppresses nothing and exists only so
the same findings are not re-investigated on every read. Waive a finding here only
when the product genuinely is not affected.

## Hygiene

- One CVE per statement; keep `impact_statement` specific and dated.
- Prefer fixing the package (rebuild picks up Wolfi patches) over waiving.
- Review waivers periodically and delete them once the CVE is fixed upstream —
  a stale `not_affected` can hide a real future regression.
