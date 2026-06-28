#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/apt-local-repos-smoke.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

TEST_COUNT=9
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
  if [ "$#" -gt 1 ] && [ -n "${2:-}" ] && [ -r "$2" ]; then
    sed 's/^/# /' "$2"
  fi
}

render_answers() {
  case_name=$1
  classes=$2
  output_path=$3
  error_path=$4

  runtime_dir="$TMP_DIR/runtime-$case_name"
  cmdline="classes=$classes primary_user=user primary_password=secret root_password=root fruux_username=alice fruux_password=token"

  if answers_file=$(
    INSTALLER_RUNTIME_DIR="$runtime_dir" \
    INSTALLER_SOURCE_ROOT="$ROOT_DIR/d-i/debian" \
    INSTALLER_CMDLINE="$cmdline" \
      sh "$ROOT_DIR/d-i/debian/scripts/preseed/answers.sh" render "$ROOT_DIR/d-i/debian" 2>"$error_path"
  ); then
    printf '%s\n' "$answers_file" >"$output_path"
    return 0
  fi

  return 1
}

answers_path() {
  sed -n '1p' "$1"
}

pkgsel_line() {
  sed -n 's/^d-i pkgsel\/include string //p' "$1" | head -n 1
}

word_list_has() {
  words=$1
  needle=$2
  case " $words " in
    *" $needle "*) return 0 ;;
  esac
  return 1
}

printf '1..%s\n' "$TEST_COUNT"

amd64_classes='lab,desktop,standard,dhcp,forky,arch/amd64,cpu/intel,gpu/generic,disk/vm'
amd64_out="$TMP_DIR/amd64.out"
amd64_err="$TMP_DIR/amd64.err"
if render_answers amd64 "$amd64_classes" "$amd64_out" "$amd64_err"; then
  amd64_answers=$(answers_path "$amd64_out")
  if grep -q '^d-i apt-setup/local3/repository string https://downloadcontent.opensuse.org/repositories/home:/cramerz:/debian/Debian_Unstable/ /$' "$amd64_answers" &&
     grep -q '^d-i apt-setup/local3/key string https://downloadcontent.opensuse.org/repositories/home:cramerz:debian/Debian_Unstable/Release.key$' "$amd64_answers"; then
    pass "forky render compacts the OBS archive onto the next consecutive local slot"
  else
    fail "forky render compacts the OBS archive onto the next consecutive local slot" "$amd64_answers"
  fi
else
  fail "forky render compacts the OBS archive onto the next consecutive local slot" "$amd64_err"
fi

if [ -n "${amd64_answers:-}" ] &&
   grep -q '^d-i apt-setup/local4/repository string https://packages.microsoft.com/repos/code stable main$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local5/repository string https://packages.microsoft.com/repos/edge stable main$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local6/repository string https://repository.mullvad.net/deb/stable stable main$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local7/repository string https://dbeaver.io/debs/dbeaver-ce /$' "$amd64_answers" &&
   grep -q '^d-i apt-setup/local8/repository string https://repository.spotify.com stable non-free$' "$amd64_answers"; then
  pass "desktop render keeps app archives consecutive after forky"
else
  fail "desktop render keeps app archives consecutive after forky" "${amd64_answers:-$amd64_err}"
fi

if [ -n "${amd64_answers:-}" ]; then
  amd64_pkgsel=$(pkgsel_line "$amd64_answers")
  if word_list_has "$amd64_pkgsel" code &&
     word_list_has "$amd64_pkgsel" microsoft-edge-stable; then
    pass "desktop amd64 package set includes code and Edge"
  else
    fail "desktop amd64 package set includes code and Edge" "$amd64_answers"
  fi
else
  fail "desktop amd64 package set includes code and Edge" "$amd64_err"
fi

desktop_only_classes='lab,desktop,standard,dhcp,arch/amd64,cpu/intel,gpu/generic,disk/vm'
desktop_only_out="$TMP_DIR/desktop-only.out"
desktop_only_err="$TMP_DIR/desktop-only.err"
if render_answers desktop-only "$desktop_only_classes" "$desktop_only_out" "$desktop_only_err"; then
  desktop_only_answers=$(answers_path "$desktop_only_out")
  if grep -q '^d-i apt-setup/local3/repository string https://packages.microsoft.com/repos/code stable main$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local4/repository string https://packages.microsoft.com/repos/edge stable main$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local5/repository string https://repository.mullvad.net/deb/stable stable main$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local6/repository string https://dbeaver.io/debs/dbeaver-ce /$' "$desktop_only_answers" &&
     grep -q '^d-i apt-setup/local7/repository string https://repository.spotify.com stable non-free$' "$desktop_only_answers"; then
    pass "desktop render shifts app archives back when forky is not selected"
  else
    fail "desktop render shifts app archives back when forky is not selected" "$desktop_only_answers"
  fi
else
  fail "desktop render shifts app archives back when forky is not selected" "$desktop_only_err"
fi

gitlab_only_classes='lab,server,standard,dhcp,service/gitlab-runner,arch/amd64,cpu/intel,gpu/generic,disk/vm'
gitlab_only_out="$TMP_DIR/gitlab-only.out"
gitlab_only_err="$TMP_DIR/gitlab-only.err"
if render_answers gitlab-only "$gitlab_only_classes" "$gitlab_only_out" "$gitlab_only_err"; then
  gitlab_only_answers=$(answers_path "$gitlab_only_out")
  if grep -q '^d-i apt-setup/local3/repository string https://packages.gitlab.com/runner/gitlab-runner/debian trixie main$' "$gitlab_only_answers"; then
    pass "gitlab-runner render shifts back when forky and apps are not selected"
  else
    fail "gitlab-runner render shifts back when forky and apps are not selected" "$gitlab_only_answers"
  fi
else
  fail "gitlab-runner render shifts back when forky and apps are not selected" "$gitlab_only_err"
fi

forky_gitlab_classes='lab,server,standard,dhcp,service/gitlab-runner,forky,arch/amd64,cpu/intel,gpu/generic,disk/vm'
forky_gitlab_out="$TMP_DIR/forky-gitlab.out"
forky_gitlab_err="$TMP_DIR/forky-gitlab.err"
if render_answers forky-gitlab "$forky_gitlab_classes" "$forky_gitlab_out" "$forky_gitlab_err"; then
  forky_gitlab_answers=$(answers_path "$forky_gitlab_out")
  if grep -q '^d-i apt-setup/local3/repository string https://downloadcontent.opensuse.org/repositories/home:/cramerz:/debian/Debian_Unstable/ /$' "$forky_gitlab_answers" &&
     grep -q '^d-i apt-setup/local4/repository string https://packages.gitlab.com/runner/gitlab-runner/debian trixie main$' "$forky_gitlab_answers"; then
    pass "gitlab-runner render shifts back behind forky when apps are not selected"
  else
    fail "gitlab-runner render shifts back behind forky when apps are not selected" "$forky_gitlab_answers"
  fi
else
  fail "gitlab-runner render shifts back behind forky when apps are not selected" "$forky_gitlab_err"
fi

desktop_gitlab_classes='lab,desktop,standard,dhcp,service/gitlab-runner,arch/amd64,cpu/intel,gpu/generic,disk/vm'
desktop_gitlab_out="$TMP_DIR/desktop-gitlab.out"
desktop_gitlab_err="$TMP_DIR/desktop-gitlab.err"
if render_answers desktop-gitlab "$desktop_gitlab_classes" "$desktop_gitlab_out" "$desktop_gitlab_err"; then
  desktop_gitlab_answers=$(answers_path "$desktop_gitlab_out")
  if grep -q '^d-i apt-setup/local8/repository string https://packages.gitlab.com/runner/gitlab-runner/debian trixie main$' "$desktop_gitlab_answers"; then
    pass "gitlab-runner render shifts back behind apps when forky is not selected"
  else
    fail "gitlab-runner render shifts back behind apps when forky is not selected" "$desktop_gitlab_answers"
  fi
else
  fail "gitlab-runner render shifts back behind apps when forky is not selected" "$desktop_gitlab_err"
fi

gitlab_classes='lab,desktop,standard,dhcp,service/gitlab-runner,forky,arch/amd64,cpu/intel,gpu/generic,disk/vm'
gitlab_out="$TMP_DIR/gitlab.out"
gitlab_err="$TMP_DIR/gitlab.err"
if render_answers gitlab "$gitlab_classes" "$gitlab_out" "$gitlab_err"; then
  gitlab_answers=$(answers_path "$gitlab_out")
  if grep -q '^d-i apt-setup/local3/repository string https://downloadcontent.opensuse.org/repositories/home:/cramerz:/debian/Debian_Unstable/ /$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local4/repository string https://packages.microsoft.com/repos/code stable main$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local5/repository string https://packages.microsoft.com/repos/edge stable main$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local6/repository string https://repository.mullvad.net/deb/stable stable main$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local7/repository string https://dbeaver.io/debs/dbeaver-ce /$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local8/repository string https://repository.spotify.com stable non-free$' "$gitlab_answers" &&
     grep -q '^d-i apt-setup/local9/repository string https://packages.gitlab.com/runner/gitlab-runner/debian trixie main$' "$gitlab_answers"; then
    pass "render preserves forky then apps then gitlab-runner when all are selected"
  else
    fail "render preserves forky then apps then gitlab-runner when all are selected" "$gitlab_answers"
  fi
else
  fail "render preserves forky then apps then gitlab-runner when all are selected" "$gitlab_err"
fi

arm64_classes='lab,desktop,standard,dhcp,forky,arch/arm64,cpu/amd,gpu/generic,disk/vm'
arm64_out="$TMP_DIR/arm64.out"
arm64_err="$TMP_DIR/arm64.err"
if render_answers arm64 "$arm64_classes" "$arm64_out" "$arm64_err"; then
  arm64_answers=$(answers_path "$arm64_out")
  arm64_pkgsel=$(pkgsel_line "$arm64_answers")
  if word_list_has "$arm64_pkgsel" code &&
     ! word_list_has "$arm64_pkgsel" microsoft-edge-stable; then
    pass "desktop non-amd64 package set skips Microsoft Edge"
  else
    fail "desktop non-amd64 package set skips Microsoft Edge" "$arm64_answers"
  fi
else
  fail "desktop non-amd64 package set skips Microsoft Edge" "$arm64_err"
fi

[ "$FAIL_COUNT" -eq 0 ]
