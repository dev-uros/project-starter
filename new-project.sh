#!/usr/bin/env bash
#
# Bootstrap a new client project from the template repositories.
#
#   ./new-project.sh client_hub
#   ./new-project.sh acme --port-base 8200 --dir ~/work
#
# Run it with no arguments and it asks for the name and the destination, so it
# works from a double click as well as from a shell. Where the project goes,
# highest precedence first:
#
#   --dir PATH                   given on the command line, asks nothing
#   PROJECTS_DIR=... in the env  for a permanently different root
#   a prompt, offering ~/Desktop/fg-projects
#
# The destination is created when it does not exist, and an existing one is
# reused. Both prompts are skipped when there is no terminal to answer them, so
# the script still works from another script or a CI job.
#
# Portability: bash, git, docker and the usual POSIX tools. No GNU-only flags,
# no realpath, no sed -i -- it runs on macOS, Linux and Git Bash on Windows.
#
# What it produces:
#
#   ~/Desktop/fg-projects/client_hub/
#     CLAUDE.md, .mcp.json, .claude/
#                   one Claude Code session from here knows every folder:
#                   the map of the folders, all MCP servers, all skills
#     Makefile      knows this project's ports; `make up`, `make web`, `make ports`
#     api/          the Laravel backend, .env written for this project
#     web/          the Vue frontend, .env written for this project
#     infra/        the shared server stack (see the note under --no-infra)
#     internal-mobile-app/
#                   the Expo app for internal users, .env.local pointing at
#                   this project's API (skipped with --no-mobile)
#
# Every container, volume and image is named after the project, so projects
# cannot overwrite each other's data. That is one variable --
# COMPOSE_PROJECT_NAME in api/.env. Host ports are the one thing a project name
# cannot separate, which is what --port-base is for.
#
# It creates files and nothing else. No container is built or started and none
# of the folders is a git repository: the templates are cloned for their
# contents and the .git directory is dropped, so a project starts with no
# history and no remotes. Run `make init` when you want it up, and `git init`
# in each folder when you are ready to put it somewhere.
#
# If anything fails before the project is complete -- a clone without access,
# a template missing a file -- what this run created is removed again, so the
# same name can simply be tried again.
#
# The trade: a fix made in a template later cannot be merged into a project made
# from it -- the two have no common ancestor, so `git merge` would conflict on
# every file. Copy the change instead.

set -euo pipefail

API_REPO="${API_REPO:-https://github.com/dev-uros/laravel-backend-ai-setup.git}"
WEB_REPO="${WEB_REPO:-https://github.com/dev-uros/vue-front-ai-setup.git}"
INFRA_REPO="${INFRA_REPO:-https://github.com/dev-uros/infra-ai-setup.git}"
MOBILE_REPO="${MOBILE_REPO:-https://github.com/dev-uros/expo-internal-ai-setup.git}"
MOBILE_DIR="internal-mobile-app"

# Ports. By default a project keeps the template's own defaults -- 8000 for the
# API, 5173 for Vite, 5433/5434 for Postgres, 6379 for Redis -- so every project
# sits on the same, memorable numbers and the script writes no port at all.
#
# That works because one project runs at a time. Two at once cannot share a host
# port: the second `docker compose up` fails with "port is already allocated",
# loudly and harmlessly. --port-base moves one of them out of the way, offsets
# below, ten ports to a block.
OFFSET_APP=0        # nginx (the API)
OFFSET_DB=1         # postgres
OFFSET_DB_TEST=2    # postgres-test
OFFSET_REDIS=3      # redis
OFFSET_GRAFANA=4    # grafana   (make observe)
OFFSET_ALLOY=5      # alloy     (make observe)
OFFSET_VITE=6       # vite dev server (the frontend)
PORT_SPAN=10        # ports reserved per project, so bases step by 10

name=""
port_base=""
parent_dir=""      # --dir, then $PROJECTS_DIR, then the prompt below
with_infra=1
with_mobile=1
run_setup=0
check_error=""

die() { printf '\n  error: %s\n\n' "$*" >&2; exit 1; }
say() { printf '  %s\n' "$*"; }

# --- paths -------------------------------------------------------------------

# `~` survives only where a shell expanded it. Quoted on the command line, or
# read from a prompt or a config file, it arrives as a literal and would create
# a directory actually called "~".
expand_tilde() {
    case "$1" in
        "~")   printf '%s\n' "$HOME" ;;
        "~/"*) printf '%s\n' "$HOME/${1#\~/}" ;;
        *)     printf '%s\n' "$1" ;;
    esac
}

# Windows puts the desktop under USERPROFILE, and OneDrive moves it again.
# A machine with no desktop at all -- a server, a plain WSL shell -- falls back
# to the home directory rather than refusing to run.
default_root() {
    local base
    for base in "${HOME:-}" "${USERPROFILE:-}"; do
        [ -n "$base" ] || continue
        [ -d "$base/Desktop" ] && { printf '%s/Desktop/fg-projects\n' "$base"; return; }
        [ -d "$base/OneDrive/Desktop" ] && { printf '%s/OneDrive/Desktop/fg-projects\n' "$base"; return; }
    done
    printf '%s/fg-projects\n' "${HOME:-.}"
}

# Can a project be created under this root? Creating it is part of the check:
# the ordinary answer on a new machine is a root that does not exist yet.
# Explains itself in $check_error rather than on stdout, so the caller can
# decide between asking again and giving up.
check_root() {
    local root=$1
    check_error=""

    [ -n "$root" ] || { check_error="the path is empty"; return 1; }
    case "$root" in
        -*) check_error="'$root' looks like an option, not a path"; return 1 ;;
    esac

    if [ -e "$root" ] && [ ! -d "$root" ]; then
        check_error="'$root' exists but is a file, not a directory"
        return 1
    fi
    if [ ! -d "$root" ]; then
        mkdir -p "$root" 2>/dev/null || {
            check_error="cannot create '$root' -- check the spelling and your permissions"
            return 1
        }
        say "created $root"
    fi
    [ -w "$root" ] || { check_error="'$root' is not writable"; return 1; }

    return 0
}

usage() {
    cat <<'USAGE'

  usage: new-project.sh [name] [options]

    [name]              lowercase letters, digits and underscores, starting
                        with a letter: client_hub.
                        Asked for when omitted.

    --port-base N       move this project's ports into a block of ten
                        starting here, for the rare case of two projects
                        running at once. By default it keeps the template's
                        own ports: API 8000, Vite 5173, Postgres 5433.
                        Between 1024 and 65526.
    --dir PATH          where the project folder is created, asked for when
                        omitted. $PROJECTS_DIR sets the answer permanently;
                        the default is ~/Desktop/fg-projects
    --no-infra          skip the infra repo -- correct when this project will be
                        deployed onto a server that already runs it
    --no-mobile         skip internal-mobile-app/, the Expo app for internal
                        users -- for a project with no mobile app
    --setup             also build the containers, migrate and install the
                        frontend dependencies -- the same as `make init`.
                        Off by default: creating a
                        project is quick, booting it is not.

USAGE
}

# --- arguments ---------------------------------------------------------------

# No arguments and no terminal is a mistake worth reporting. No arguments WITH a
# terminal is the double-click case, and both prompts below handle it.
if [ $# -eq 0 ] && [ ! -t 0 ]; then
    usage
    exit 1
fi

# An option at the end of the line, or followed by another option, has no value.
# Without this check `shift 2` fails under `set -e` and the script ends with no
# message at all.
need_value() {
    case "${2:-}" in
        ""|-*) die "$1 needs a value" ;;
    esac
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)   usage; exit 0 ;;
        --port-base) need_value "$@"; port_base=$2; shift 2 ;;
        --dir)       need_value "$@"; parent_dir=$2; shift 2 ;;
        --no-infra)  with_infra=0; shift ;;
        --no-mobile) with_mobile=0; shift ;;
        --setup)     run_setup=1; shift ;;
        --no-setup)  run_setup=0; shift ;;   # accepted, and now the default
        -*)          die "unknown option: $1" ;;
        *)
            [ -z "$name" ] || die "give exactly one project name"
            name="$1"; shift ;;
    esac
done

command -v git >/dev/null || die "git is not installed"
command -v docker >/dev/null || die "docker is not installed"

# --- the name ----------------------------------------------------------------

# Docker Compose wants lowercase and a leading letter; an uppercase letter here
# fails much later, inside compose, with a message that does not mention this
# script. Compose would take a hyphen too, but the name is also the Postgres
# database and user, where a hyphen has to be quoted in every piece of SQL.
name_ok() { printf '%s' "$1" | grep -qE '^[a-z][a-z0-9_]*$'; }

while ! name_ok "$name"; do
    [ -z "$name" ] || say "'$name' will not do: lowercase letters, digits and _, starting with a letter"
    # `|| die` rather than a bare read: on Ctrl-D read returns non-zero, and
    # under `set -e` that would end the script silently, mid-sentence.
    [ -t 0 ] || die "give a project name (lowercase letters, digits and _)"
    printf '\n  project name?\n  > '
    read -r name || { printf '\n'; die "cancelled"; }
done

# --- where it goes -----------------------------------------------------------

DEFAULT_PARENT_DIR=$(default_root)

if [ -n "$parent_dir" ]; then
    parent_dir=$(expand_tilde "$parent_dir")
    check_root "$parent_dir" || die "$check_error"           # --dir
elif [ -n "${PROJECTS_DIR:-}" ]; then
    parent_dir=$(expand_tilde "$PROJECTS_DIR")
    check_root "$parent_dir" || die "$check_error"           # $PROJECTS_DIR
elif [ -t 0 ]; then
    while :; do
        printf '\n  where should %s be created?\n  [%s] ' "$name" "$DEFAULT_PARENT_DIR"
        read -r answer || { printf '\n'; die "cancelled"; }
        parent_dir=$(expand_tilde "${answer:-$DEFAULT_PARENT_DIR}")
        check_root "$parent_dir" && break
        say "$check_error"
    done
else
    # No terminal to ask -- called from another script, or from CI. A default
    # beats hanging on a read that nothing will ever answer.
    parent_dir="$DEFAULT_PARENT_DIR"
    check_root "$parent_dir" || die "$check_error"
fi

# Absolute from here on. A relative answer would otherwise reach the
# instructions this prints at the end, where it means something different from
# wherever it is pasted. `cd`+`pwd` rather than realpath, which macOS did not
# ship before 12.
parent_dir=$(cd "$parent_dir" && pwd)

dir="$parent_dir/$name"

if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
    die "there is already a project called '$name' in $parent_dir -- pick another name, or remove $dir first"
fi

# --- ports -------------------------------------------------------------------

# True when nothing is listening. Uses bash's own /dev/tcp so the script needs
# no nc, lsof or ss -- their flags differ between macOS and Linux.
port_free() {
    ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# A host port is 1..65535, and below 1024 docker needs root on Linux. A leading
# zero is refused too: bash arithmetic would read 08100 as octal.
port_ok() {
    printf '%s' "$1" | grep -qE '^[1-9][0-9]*$' && [ "$1" -le 65535 ]
}

if [ -n "$port_base" ]; then
    max_base=$((65535 - PORT_SPAN + 1))
    { port_ok "$port_base" && [ "$port_base" -ge 1024 ] && [ "$port_base" -le "$max_base" ]; } ||
        die "--port-base must be a number between 1024 and $max_base"
fi

# --- target directory --------------------------------------------------------

# Until the project is complete, a failure removes what this run created. A
# half-cloned folder would otherwise block the next run with "already a project
# called ...". Only the paths this script writes are removed, and the folder
# itself only when this run created it -- an empty one made by hand stays.
dir_created=0
[ -d "$dir" ] || dir_created=1
finished=0

cleanup() {
    [ "$finished" -eq 0 ] || return 0
    rm -rf "$dir/api" "$dir/web" "$dir/infra" "$dir/$MOBILE_DIR" "$dir/Makefile" \
        "$dir/CLAUDE.md" "$dir/.mcp.json" "$dir/.claude"
    [ "$dir_created" -eq 0 ] || rmdir "$dir" 2>/dev/null || true
    printf '  removed the unfinished project, %s\n\n' "$dir" >&2
}
trap cleanup EXIT
# The EXIT trap alone is not enough for Ctrl-C everywhere; exiting explicitly
# makes the trap run on every bash this supports.
trap 'exit 130' INT TERM

# The root was checked and created above; $dir is absolute because $parent_dir
# is, and the name has already been proved free.
mkdir -p "$dir" || die "cannot create $dir"

# client_hub -> Client Hub
title=$(printf '%s' "$name" | tr '_-' '  ' | awk '{for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2); print}')

printf '\n  %s  (%s)\n' "$title" "$name"
printf '  %s\n\n' "$dir"

# --- clone -------------------------------------------------------------------

clone() {
    local url=$1 target=$2
    say "copying $(basename "$url" .git) -> $target/"
    # --depth 1 because the history is thrown away on the next line anyway, and
    # the frontend's is not small.
    git clone --quiet --depth 1 "$url" "$dir/$target"
    # The project starts clean: no history, no origin, not a repository at all.
    # `git init` it when there is somewhere to push it.
    rm -rf "$dir/$target/.git"
}

clone "$API_REPO" api
clone "$WEB_REPO" web
[ "$with_infra" -eq 1 ] && clone "$INFRA_REPO" infra
[ "$with_mobile" -eq 1 ] && clone "$MOBILE_REPO" "$MOBILE_DIR"

# --- environment -------------------------------------------------------------

# Replace KEY=... in place, or append it when the key is absent. Written in
# shell rather than with sed -i, whose in-place flag takes an argument on macOS
# and does not on Linux.
set_env() {
    local key=$1 val=$2 file=$3 tmp line
    tmp=$(mktemp)
    if grep -qE "^${key}=" "$file"; then
        while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
                "${key}="*) printf '%s=%s\n' "$key" "$val" ;;
                *)          printf '%s\n' "$line" ;;
            esac
        done < "$file" > "$tmp"
    else
        cat "$file" > "$tmp"
        printf '%s=%s\n' "$key" "$val" >> "$tmp"
    fi
    mv "$tmp" "$file"
}

# Every occurrence of a literal string, replaced in place -- the same
# portability reason as set_env.
replace_in_file() {
    local from=$1 to=$2 file=$3 tmp line
    tmp=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
        printf '%s\n' "${line//"$from"/$to}"
    done < "$file" > "$tmp"
    mv "$tmp" "$file"
}

say "writing api/.env"
cp "$dir/api/.env.example" "$dir/api/.env"

# Reads a value back out of the file just written. With no --port-base the
# template's own defaults are kept and no port is written at all, so this is
# what tells the Makefile and the summary below which numbers the project ended
# up on -- rather than a second copy of those defaults, kept in this script,
# quietly going stale the day the template moves one.
read_env() { sed -n "s/^$1=//p" "$dir/api/.env" | tail -n1; }

if [ -n "$port_base" ]; then
    app_port=$((port_base + OFFSET_APP))
    db_port=$((port_base + OFFSET_DB))
    db_test_port=$((port_base + OFFSET_DB_TEST))
    redis_port=$((port_base + OFFSET_REDIS))
    grafana_port=$((port_base + OFFSET_GRAFANA))
    alloy_port=$((port_base + OFFSET_ALLOY))
    vite_port=$((port_base + OFFSET_VITE))

    set_env APP_PORT             "$app_port"                   "$dir/api/.env"
    set_env FORWARD_DB_PORT      "$db_port"                    "$dir/api/.env"
    set_env FORWARD_TEST_DB_PORT "$db_test_port"               "$dir/api/.env"
    set_env FORWARD_REDIS_PORT   "$redis_port"                 "$dir/api/.env"
    set_env GRAFANA_PORT         "$grafana_port"               "$dir/api/.env"
    set_env ALLOY_PORT           "$alloy_port"                 "$dir/api/.env"
    # Where the emailed activation and reset links point, and the one origin
    # CORS lets into the API from a browser.
    set_env FRONTEND_URL         "http://localhost:$vite_port"  "$dir/api/.env"
else
    app_port=$(read_env APP_PORT)
    db_port=$(read_env FORWARD_DB_PORT)
    db_test_port=$(read_env FORWARD_TEST_DB_PORT)
    redis_port=$(read_env FORWARD_REDIS_PORT)
    grafana_port=$(read_env GRAFANA_PORT)
    alloy_port=$(read_env ALLOY_PORT)
    # The frontend has no port variable of its own -- VITE_API_URL is its only
    # one, by its own rule -- so the dev server's port lives in the API's
    # FRONTEND_URL, which is the one place the two halves have to agree.
    vite_port=$(read_env FRONTEND_URL | sed -E 's|^.*:([0-9]+)/?$|\1|')

    # Read, not written, so a template that renames or drops one of these keys
    # would otherwise produce a Makefile with an empty port -- and a `make web`
    # that fails far from the cause.
    for pair in "APP_PORT=$app_port" "FORWARD_DB_PORT=$db_port" \
                "FORWARD_TEST_DB_PORT=$db_test_port" "FORWARD_REDIS_PORT=$redis_port" \
                "GRAFANA_PORT=$grafana_port" "ALLOY_PORT=$alloy_port" \
                "FRONTEND_URL=$vite_port"; do
        port_ok "${pair#*=}" ||
            die "api/.env.example has no usable ${pair%%=*} (found '${pair#*=}') -- has the template renamed it?"
    done
fi

set_env APP_URL "http://localhost:$app_port" "$dir/api/.env"

# The one line that renames every container, volume and image of this stack.
set_env COMPOSE_PROJECT_NAME "$name"          "$dir/api/.env"
set_env APP_NAME             "\"$title\""     "$dir/api/.env"
set_env DB_DATABASE          "$name"          "$dir/api/.env"
set_env DB_USERNAME          "$name"          "$dir/api/.env"

# Warn, never refuse. Something listening here is almost always another project
# still up, which `make down` fixes -- and a wrong guess must not stop a project
# from being created.
busy=""
for p in "$app_port" "$db_port" "$db_test_port" "$redis_port" "$vite_port"; do
    port_free "$p" || busy="$busy $p"
done
if [ -n "$busy" ]; then
    say "warning: something is already listening on:$busy"
    say "another project is probably running -- \`make down\` there, or pass --port-base"
fi

say "writing web/.env"
cp "$dir/web/.env.example" "$dir/web/.env"
# VITE_API_URL is the only VITE_ variable the frontend has, by its own rule.
# The dev server's port is not one -- it is passed on the command line, which
# is what `make web` in the generated Makefile does.
set_env VITE_API_URL "http://localhost:$app_port/api" "$dir/web/.env"

if [ "$with_mobile" -eq 1 ]; then
    say "writing $MOBILE_DIR/.env.local"
    cp "$dir/$MOBILE_DIR/.env.example" "$dir/$MOBILE_DIR/.env.local"
    # localhost is the simulator's own loopback, which is the Mac's on iOS; the
    # Android emulator reaches it through `adb reverse` on the same port, which
    # `make mobile-android` sets up. A physical phone needs the Mac's LAN
    # address here instead.
    set_env EXPO_PUBLIC_API_URL "http://localhost:$app_port/api" "$dir/$MOBILE_DIR/.env.local"
    # EAS_PROJECT_ID and EXPO_OWNER stay empty: they belong to the client's
    # Expo account, set up once per project -- see
    # internal-mobile-app/docs/push-notifications.md.

    # The app is called after the project, like APP_NAME in api/.env: the name
    # under the icon and in the permission texts. The template's placeholder
    # appears nowhere else in app.json. Bundle id, package and slug stay as
    # they are -- the client's Apple and Firebase keys are bound to the first
    # two, and the Maestro flows to all three; changing them is step 0 of
    # docs/push-notifications.md.
    say "naming the mobile app $title"
    replace_in_file "Backoffice" "$title" "$dir/$MOBILE_DIR/app.json"
    grep -q "\"name\": \"$title\"" "$dir/$MOBILE_DIR/app.json" ||
        die "$MOBILE_DIR/app.json has no \"name\": \"Backoffice\" -- has the template renamed it?"
fi

# --- workspace Makefile ------------------------------------------------------

say "writing Makefile"
{
    printf '# %s -- workspace helper. Each repo keeps its own Makefile;\n' "$title"
    printf '# this one only knows the port block the project was created with.\n\n'
    printf 'PROJECT      := %s\n' "$name"
    printf 'APP_PORT     := %s\n' "$app_port"
    printf 'VITE_PORT    := %s\n' "$vite_port"
    printf 'GRAFANA_PORT := %s\n' "$grafana_port"
    printf 'DB_PORT      := %s\n' "$db_port"
    printf 'REDIS_PORT   := %s\n\n' "$redis_port"
    cat <<'MAKEFILE'
.DEFAULT_GOAL := help

.PHONY: init
init: ## First run: boot, migrate, seed the first user, install frontend deps
	@$(MAKE) -C api setup
	@$(MAKE) -C api artisan c="db:seed --force"
	cd web && npm install
MAKEFILE
    if [ "$with_mobile" -eq 1 ]; then
        # npm ci, not install: the lockfile holds the SDK-matched versions, and
        # a fresh project must not resolve anything differently.
        printf '\tcd %s && npm ci\n' "$MOBILE_DIR"
    fi
    cat <<'MAKEFILE'
	@echo ""
	@echo "  the first administrator is seeded by"
	@echo "  api/database/seeders/UserSeeder.php -- password: password"
	@echo ""

.PHONY: up
up: ## Start the API stack (postgres, redis, php, horizon, scheduler, nginx)
	@$(MAKE) -C api up

.PHONY: down
down: ## Stop the API stack (data volumes are kept)
	@$(MAKE) -C api down

.PHONY: web
web: ## Run the frontend dev server on this project's port
	cd web && npm run dev -- --port $(VITE_PORT) --strictPort

MAKEFILE
    if [ "$with_mobile" -eq 1 ]; then
        printf 'MOBILE_DIR   := %s\n\n' "$MOBILE_DIR"
        cat <<'MAKEFILE'
.PHONY: mobile
mobile: ## Run Metro for the mobile app (the dev build must be installed)
	cd $(MOBILE_DIR) && npx expo start --dev-client --port 8081

.PHONY: mobile-ios
mobile-ios: ## Build the mobile dev build and run it on the iOS simulator
	cd $(MOBILE_DIR) && npm run ios

.PHONY: mobile-android
mobile-android: ## Build the mobile dev build and run it on the Android emulator
	adb reverse tcp:$(APP_PORT) tcp:$(APP_PORT)
	cd $(MOBILE_DIR) && npm run android

MAKEFILE
    fi
    cat <<'MAKEFILE'
.PHONY: observe
observe: ## Start Grafana + Loki + Alloy for this project
	@$(MAKE) -C api observe

.PHONY: test
test: ## Run the API test suite
	@$(MAKE) -C api test

.PHONY: ports
ports: ## Show which host port belongs to what
	@echo ""
	@echo "  $(PROJECT)"
	@echo ""
	@echo "  api        http://localhost:$(APP_PORT)"
	@echo "  docs       http://localhost:$(APP_PORT)/docs/api"
	@echo "  horizon    http://localhost:$(APP_PORT)/horizon"
	@echo "  web        http://localhost:$(VITE_PORT)"
ifdef MOBILE_DIR
	@echo "  metro      http://localhost:8081   (make mobile)"
endif
	@echo "  grafana    http://localhost:$(GRAFANA_PORT)   (make observe)"
	@echo "  postgres   localhost:$(DB_PORT)"
	@echo "  redis      localhost:$(REDIS_PORT)"
	@echo ""

.PHONY: help
help: ## Show this help
	@echo ""
	@echo "  usage: make <target>"
	@echo ""
	@grep -hE "^[a-zA-Z_-]+:.*?## .*$$" $(MAKEFILE_LIST) \
		| awk "BEGIN {FS = \":.*?## \"}; {printf \"  \033[36m%-15s\033[0m %s\n\", \$$1, \$$2}"
	@echo ""
MAKEFILE
} > "$dir/Makefile"

# --- one Claude Code session for the whole project ---------------------------

# The project is meant to be worked on from its root: one session that knows
# every folder, instead of one per folder. Claude Code reads CLAUDE.md, .mcp.json
# and .claude/ only from the folder a session starts in, so the root gets its
# own -- a map of the folders, every template's MCP servers, and links to every
# template's skills. A session started inside one folder still works and loads
# only that folder's set.

# Claude Code reads CLAUDE.md, never AGENTS.md. The frontend links one to the
# other; a template that forgets to would have its rules silently ignored.
for d in web "$MOBILE_DIR"; do
    [ -f "$dir/$d/AGENTS.md" ] || continue
    [ -e "$dir/$d/CLAUDE.md" ] || [ -L "$dir/$d/CLAUDE.md" ] ||
        (cd "$dir/$d" && ln -s AGENTS.md CLAUDE.md)
done

say "writing CLAUDE.md, .mcp.json and .claude/ for working from the root"

infra_row=""
[ "$with_infra" -eq 1 ] &&
    infra_row='| `infra/` | the shared server stack: Traefik and the log stack (Loki, Alloy, Grafana). No application lives here | `infra/README.md`, and `infra/docs/server-setup.md` for a server from scratch |
'
mobile_row=""
mobile_contract=""
mobile_mcp=""
mobile_cmd=""
if [ "$with_mobile" -eq 1 ]; then
    mobile_row="| \`$MOBILE_DIR/\` | Expo app for internal (backoffice) users -- React Native, Expo Router, TanStack Query, Zod. iOS and Android, no web target | \`$MOBILE_DIR/AGENTS.md\`. A new screen or feature goes through the \`new-feature\` skill |
"
    mobile_contract=" and \`$MOBILE_DIR/\`"
    mobile_mcp="- **maestro** -- drives the iOS simulator and Android emulator for the
  mobile app's end-to-end flows. Needs the \`maestro\` CLI installed and a
  dev build running (\`make mobile-ios\` / \`make mobile-android\`).
- The **Expo plugin** (\`.claude/settings.json\`) -- the \`expo:*\` skills and
  Expo's MCP tools. The mobile rules require checking Expo's docs before
  touching any Expo or React Native API: Expo changes every SDK release.
"
    mobile_cmd="- mobile: \`cd $MOBILE_DIR && ...\` -- packages only through
  \`npx expo install\`, never a bare \`npm install <pkg>\`, so the versions
  match the SDK.
"
fi

cat > "$dir/CLAUDE.md" <<CLAUDE
# $title -- project root

One project, several stacks. This root is where work starts: describe the task,
and the folders below say how each part of it is done. Each folder has its own
rules, its own toolchain and its own deploy -- a change in \`web/\` does not
redeploy the API.

| Folder | What | Read before touching it |
| --- | --- | --- |
| \`api/\` | Laravel API, runs in Docker (\`make\` targets, never bare \`php\`/\`artisan\`/\`composer\` on the host) | \`api/CLAUDE.md\`, then every row of \`api/.ai/rules/index.md\` whose globs match the files you touch |
| \`web/\` | Vue 3 SPA for the backoffice (Vite, Nuxt UI as a component library, Pinia Colada) | \`web/AGENTS.md\` |
${mobile_row}${infra_row}
**Those files are the contract; this one only points at them.** Read the
matching file before the first edit in a folder, even for a small change -- the
rules there are specific to this codebase and override general habits.

## A task that crosses folders

The API is the source of truth for every client. \`api/docs/frontend-integration.md\`
is the contract between the API and \`web/\`${mobile_contract}, and the reference
generated from the code is at \`/docs/api\` on the running API (\`make ports\`).
A change to a response shape, a new endpoint or a new validation message is made
in \`api/\` first, documented there in the same change, and then used by the
clients -- each by its own rules. It has to satisfy every side it touches.

The API's \`message\` field is written for the end user, in Serbian, and the
clients show it as it arrives.

## Commands run inside their folder

Paths and commands in each folder's rules are relative to that folder.

- api: \`make -C api <target>\` (\`make -C api help\` lists them); artisan as
  \`make -C api artisan c="..."\`. The containers must be up: \`make up\`.
- web: \`cd web && npm ...\`
${mobile_cmd}
The workspace \`Makefile\` here starts things: \`make help\` lists \`up\`, \`down\`,
\`web\`, \`test\`, \`ports\`$( [ "$with_mobile" -eq 1 ] && printf ', `mobile`, `mobile-ios`, `mobile-android`' ).

## Skills and MCP are wired up at this root

\`.mcp.json\` here holds the MCP servers every folder's own \`.mcp.json\`
declares, so a session started in this folder has all of them:

- **laravel-boost** -- Laravel docs search, \`database-query\`, \`database-schema\`,
  \`tinker\`, \`browser-logs\`. Runs **inside the \`php\` container**
  (\`docker compose -f api/compose.yaml exec\`), not on the host: \`DB_HOST=postgres\`
  only resolves inside the Compose network. The containers must be up (\`make up\`).
- **nuxt-ui**, **zod** -- hosted servers. Querying \`nuxt-ui\` for props, slots
  and examples before writing a \`U*\` component is mandatory (\`web/AGENTS.md\`).
- **playwright** -- a live browser, for checking the SPA.
${mobile_mcp}
\`.claude/skills/\` holds links to every skill in \`api/.claude/skills/\`,
\`web/.claude/skills/\`$( [ "$with_mobile" -eq 1 ] && printf ' and `%s/.claude/skills/`' "$MOBILE_DIR" ). Use the skill a
folder's rules name for the task. Edit a skill in the folder that owns it, never
through the link, and add a link here when a new one is installed there.
CLAUDE

{
    printf '{\n  "mcpServers": {\n'
    cat <<'MCP'
    "laravel-boost": {
      "type": "stdio",
      "command": "docker",
      "args": ["compose", "-f", "api/compose.yaml", "exec", "-T", "--user", "www-data", "php", "php", "artisan", "boost:mcp"]
    },
    "nuxt-ui": {
      "type": "http",
      "url": "https://ui.nuxt.com/mcp"
    },
    "zod": {
      "type": "http",
      "url": "https://mcp.inkeep.com/zod/mcp"
    },
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@playwright/mcp@latest"],
      "env": {}
    }
MCP
    if [ "$with_mobile" -eq 1 ]; then
        cat <<'MCP'
    ,
    "maestro": {
      "type": "stdio",
      "command": "maestro",
      "args": ["mcp"],
      "env": {}
    }
MCP
    fi
    printf '  }\n}\n'
} > "$dir/.mcp.json"

# The root's servers are written above rather than merged from the templates --
# merging JSON portably needs a tool this script does not require, and boost has
# to be rewritten to run in the container anyway. So say when a template has
# gained a server the root does not know about.
mcp_names() {
    grep -oE '^ *"[^"]+": *\{' "$1" | sed -E 's/^ *"([^"]+)".*/\1/' |
        grep -vxE 'mcpServers|env|headers' || true
}
for d in api web "$MOBILE_DIR"; do
    [ -f "$dir/$d/.mcp.json" ] || continue
    for server in $(mcp_names "$dir/$d/.mcp.json"); do
        grep -q "\"$server\":" "$dir/.mcp.json" ||
            say "warning: $d/.mcp.json declares '$server', which the root .mcp.json does not -- add it to new-project.sh"
    done
done

mkdir -p "$dir/.claude/skills"

if [ "$with_mobile" -eq 1 ]; then
    cat > "$dir/.claude/settings.json" <<'SETTINGS'
{
  "enabledPlugins": {
    "expo@claude-plugins-official": true
  }
}
SETTINGS
    # Same reasoning as .mcp.json: copied by hand, so report a difference.
    if [ -f "$dir/$MOBILE_DIR/.claude/settings.json" ] &&
        ! cmp -s "$dir/$MOBILE_DIR/.claude/settings.json" "$dir/.claude/settings.json"; then
        say "warning: $MOBILE_DIR/.claude/settings.json differs from the root's -- check what it added"
    fi
fi

# Links, not copies, so a skill updated in its folder is updated at the root.
# (Git Bash on Windows copies instead unless symlinks are enabled -- still
# loads, but goes stale.) Two folders shipping a skill of the same name would
# leave one of them unreachable from here, so that stops the run.
for d in api web "$MOBILE_DIR"; do
    [ -d "$dir/$d/.claude/skills" ] || continue
    for skill in "$dir/$d/.claude/skills"/*/; do
        [ -d "$skill" ] || continue
        skill=$(basename "$skill")
        [ ! -e "$dir/.claude/skills/$skill" ] ||
            die "the skill '$skill' is in two templates -- rename one of them"
        ln -s "../../$d/.claude/skills/$skill" "$dir/.claude/skills/$skill"
    done
done

# Every file is in place. From here on a failure -- in the build below -- leaves
# a complete project that only needs booting, so it is kept.
finished=1

# --- first run ---------------------------------------------------------------

if [ "$run_setup" -eq 1 ] && ! command -v make >/dev/null; then
    say "make not found -- skipping the build"
    say "install make, then run: make -C \"$dir\" init"
    run_setup=0
fi

if [ "$run_setup" -eq 1 ]; then
    printf '\n'
    say "building, booting, migrating and seeding (a few minutes the first time)"
    printf '\n'
    # The generated Makefile owns the order of these steps, so --setup and a
    # later `make init` cannot drift apart.
    make -C "$dir" init ||
        die "$title was created, but booting it failed -- fix the error above, then run: make -C \"$dir\" init"
fi

# --- what to do next ---------------------------------------------------------

mobile_next=""
if [ "$with_mobile" -eq 1 ]; then
    mobile_next="
  The mobile app is in $MOBILE_DIR/ and talks to this API:
    make mobile-ios     build the dev build on the iOS simulator
    make mobile-android the same on the Android emulator
    make mobile         Metro only, once a dev build is installed
  Push notifications need the client's Expo, Firebase and Apple
  accounts -- $MOBILE_DIR/docs/push-notifications.md.
  Crash reports go to Sentry once the project has one --
  $MOBILE_DIR/docs/sentry.md.
"
fi

if [ "$run_setup" -eq 1 ]; then
    booted="    make ports          what is on which port
    make web            start the frontend"
else
    booted="    make init           boot it, migrate and seed (first time, a few minutes)
    make ports          what is on which port"
fi

cat <<NEXT

  ------------------------------------------------------------------
  $title is ready.

    cd $dir
$booted

  api       http://localhost:$app_port
  docs      http://localhost:$app_port/docs/api
  web       http://localhost:$vite_port
$mobile_next
  Containers are named ${name}-php-1, ${name}-postgres-1, and so on,
  so this project cannot collide with another one on this machine.

  None of the folders is a git repository yet. When you have
  somewhere to push each one:

    cd api && git init && git add -A && git commit -m "Initial commit"
    git branch -M main && git remote add origin <url> && git push -u origin main

  \`make init\` seeds the first administrator -- the address and the
  development password are in api/database/seeders/UserSeeder.php, and
  editing that file before the first run is how you change them. For a
  real address on a real server, once SMTP works:

    make -C api artisan c="admin:create you@example.com --name=... --surname=..."
  ------------------------------------------------------------------

NEXT
