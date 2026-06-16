#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

TEST_COUNT=6
TEST_INDEX=0
FAIL_COUNT=0

pass() {
  TEST_INDEX=$((TEST_INDEX + 1))
  printf 'ok %s - %s\n' "$TEST_INDEX" "$1"
}

fail() {
  TEST_INDEX=$((TEST_INDEX + 1))
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'not ok %s - %s\n' "$TEST_INDEX" "$1"
}

printf '1..%s\n' "$TEST_COUNT"

install_conf="$ROOT_DIR/d-i/debian/classes/install.conf"
system_cfg="$ROOT_DIR/d-i/debian/classes/configs/system.cfg"
addons_cfg="$ROOT_DIR/d-i/debian/classes/configs/addons.cfg"
early_dispatch="$ROOT_DIR/d-i/debian/scripts/early/dispatch.sh"
partman_dispatch="$ROOT_DIR/d-i/debian/scripts/partman/dispatch.sh"
late_dispatch="$ROOT_DIR/d-i/debian/scripts/late/dispatch.sh"
tmp_report=$(mktemp "${TMPDIR:-/tmp}/class-topology-smoke.XXXXXX")
trap 'rm -f "$tmp_report"' EXIT HUP INT TERM

if grep -q '^Config: classes/configs/groups.cfg$' "$install_conf" &&
   grep -q '^Config: classes/configs/hardware.cfg$' "$install_conf" &&
   grep -q '^Config: classes/configs/system.cfg$' "$install_conf" &&
   grep -q '^Config: classes/configs/storage.cfg$' "$install_conf" &&
   grep -q '^Config: classes/configs/addons.cfg$' "$install_conf"; then
  pass "install.conf enumerates the canonical class metadata files"
else
  fail "install.conf enumerates the canonical class metadata files"
fi

if python3 - "$ROOT_DIR" >"$tmp_report" <<'PY'
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
class_root = root / "d-i/debian/classes"


def load_records(path: pathlib.Path):
    records = []
    current = {}
    for lineno, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.rstrip("\r")
        if not line:
            if current:
                records.append(current)
                current = {}
            continue
        if line.startswith("#"):
            continue
        if ": " not in line:
            raise SystemExit(f"malformed config line {path}:{lineno}: {line}")
        key, value = line.split(": ", 1)
        if key in current:
            raise SystemExit(f"duplicate field {path}:{lineno}: {key}")
        current[key] = value
    if current:
        records.append(current)
    return records


group_records = load_records(class_root / "configs/groups.cfg")
class_records = []
for name in ("hardware.cfg", "system.cfg", "storage.cfg", "addons.cfg"):
    class_records.extend(load_records(class_root / "configs" / name))

group_source = {}
for record in group_records:
    if record.get("Type") != "group":
        raise SystemExit(f"non-group record in groups.cfg: {record!r}")
    group_source[record["Name"]] = record.get("Source", "class-select")

helper_roots = {
    "LateHelper": root / "d-i/debian/scripts/late",
    "EarlyHelper": root / "d-i/debian/scripts/early",
    "PartmanHelper": root / "d-i/debian/scripts/partman",
}

errors = []
manifest_paths = set()
for record in class_records:
    if record.get("Type") != "class":
        errors.append(f"class config contains non-class record: {record!r}")
        continue
    group = record.get("Group", "")
    name = record.get("Name", "")
    if not group or not name:
        errors.append(f"class record is missing Group/Name: {record!r}")
        continue
    source = group_source.get(group)
    if source is None:
        errors.append(f"class record references unknown group {group}: {record!r}")
        continue
    if source == "class-auto":
        rel = pathlib.Path("d-i/debian/classes/class-auto") / group / f"{name}.cfg"
    elif source == "class-select":
        rel = pathlib.Path("d-i/debian/classes/class-select") / group / f"{name}.cfg"
    elif source == "class-addon":
        rel = pathlib.Path("d-i/debian/classes/class-addon") / f"{name}.cfg"
    else:
        errors.append(f"unknown source for group {group}: {source}")
        continue
    manifest_paths.add(rel.as_posix())
    if not (root / rel).is_file():
        errors.append(f"configured class {group}/{name} is missing fragment {rel}")
    for helper_key, helper_root in helper_roots.items():
        helper_name = record.get(helper_key, "").strip()
        if helper_name and not (helper_root / f"{helper_name}.sh").is_file():
            errors.append(f"class {group}/{name} references missing {helper_key} script {helper_root / (helper_name + '.sh')}")

actual_paths = set()
for rel in sorted((class_root / "class-select").rglob("*.cfg")):
    actual_paths.add(rel.relative_to(root).as_posix())
for rel in sorted((class_root / "class-auto").rglob("*.cfg")):
    actual_paths.add(rel.relative_to(root).as_posix())
for rel in sorted((class_root / "class-addon").glob("*.cfg")):
    actual_paths.add(rel.relative_to(root).as_posix())

for orphan in sorted(actual_paths - manifest_paths):
    errors.append(f"orphan class fragment without config record: {orphan}")

if errors:
    print("\n".join(errors))
    raise SystemExit(1)
PY
then
  pass "every configured class record resolves to a fragment and helper scripts stay coherent"
else
  sed 's/^/# /' "$tmp_report"
  fail "every configured class record resolves to a fragment and helper scripts stay coherent"
fi

if grep -q '^Name: gitlab-runner$' "$system_cfg" &&
   grep -q '^Description: GitLab Runner service role$' "$system_cfg" &&
   ! grep -q '^LateHelper: gitlab-runner-service$' "$system_cfg" &&
   grep -q '^Name: podman$' "$addons_cfg" &&
   ! grep -q '^LateHelper: podman-addon$' "$addons_cfg" &&
   grep -q '^Name: ssh$' "$addons_cfg" &&
   ! grep -q '^LateHelper: ssh-server$' "$addons_cfg" &&
   grep -q '^LateHelper: devops$' "$addons_cfg" &&
   grep -q '^LateHelper: web$' "$system_cfg" &&
   grep -q '^LateHelper: db$' "$system_cfg"; then
  pass "package-selected and helper-driven classes keep the intended split in config metadata"
else
  fail "package-selected and helper-driven classes keep the intended split in config metadata"
fi

if grep -q '"\$helper_dest" "\$@" </dev/null' "$early_dispatch" &&
   grep -q '"\$helper_dest" "\$@" </dev/null' "$partman_dispatch" &&
   grep -q '"\$helper_dest" "\$@" </dev/null 3>&- 4>&- 5>&- 6>&- 7>&- 8>&- 9>&-' "$late_dispatch" &&
   grep -q 'helper_sorted="${helper_dir}/selected-helpers.sorted.tsv"' "$late_dispatch" &&
   grep -q 'helper_order=$(installer_class_helper_order' "$late_dispatch" &&
   grep -q 'sort -t "$(printf '\''\\t'\'')" -k1,1n -k2,2 -k3,3 "$helper_records" >"$helper_sorted"' "$late_dispatch"; then
  pass "dispatchers detach helper stdin and late helpers are sorted deterministically"
else
  fail "dispatchers detach helper stdin and late helpers are sorted deterministically"
fi

readme="$ROOT_DIR/README.md"
deprecated_conf="$ROOT_DIR/d-i/debian/classes/CLASSES.conf"
if grep -q 'classes/install.conf' "$readme" &&
   grep -q 'state/plan.tsv' "$readme" &&
   grep -q '^# Deprecated source file\.$' "$deprecated_conf" &&
   grep -q '^# - classes/install.conf$' "$deprecated_conf"; then
  pass "docs and deprecated CLASSES.conf pointer align with the config-backed topology"
else
  fail "docs and deprecated CLASSES.conf pointer align with the config-backed topology"
fi

class_plan_test="$ROOT_DIR/t/class-plan-smoke.sh"
if grep -q 'RejectedClasses: addon/podman' "$class_plan_test" &&
   grep -q 'runtime install.conf is generated from the config-backed class plan' "$class_plan_test" &&
   grep -q 'generated plan.tsv contains manifest, group, and class rows' "$class_plan_test"; then
  pass "class-plan smoke test covers generated plan output, runtime install.conf, and rejected-class policy"
else
  fail "class-plan smoke test covers generated plan output, runtime install.conf, and rejected-class policy"
fi

[ "$FAIL_COUNT" -eq 0 ]
