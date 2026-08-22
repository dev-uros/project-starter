#!/usr/bin/env bash
#
# Bootstrap a new client project from the three template repositories.
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
# The path also decides which projects the port-block scan can see, so keep
# every project under one root unless you pass --port-base by hand.
#
# Portability: bash, git, docker and the usual POSIX tools. No GNU-only flags,
# no realpath, no sed -i -- it runs on macOS, Linux and Git Bash on Windows.
#
# What it produces:
#
#   ~/Desktop/fg-projects/client_hub/
#     Makefile      knows this project's port block; `make up`, `make web`, `make ports`
#     api/          the Laravel backend, .env written for this project
#     web/          the Vue frontend, .env written for this project
#     infra/        the shared server stack (see the note under --no-infra)
#
# Every container, volume and image is named after the project, so two client
# projects can run side by side without touching each other. That is one
# variable -- COMPOSE_PROJECT_NAME in api/.env -- plus a block of host ports.
#
# It creates files and nothing else. No container is built or started and none
# of the three folders is a git repository: the templates are cloned for their
# contents and the .git directory is dropped, so a project starts with no
# history and no remotes. Run `make setup` when you want it up, and `git init`
# in each folder when you are ready to put it somewhere.
#
# The trade: a fix made in a template later cannot be merged into a project made
# from it -- the two have no common ancestor, so `git merge` would conflict on
# every file. Copy the change, or pass --setup and keep the clones' history by
# hand if a project needs to track the template.

set -euo pipefail

API_REPO="${API_REPO:-https://github.com/dev-uros/laravel-backend-ai-setup.git}"
WEB_REPO="${WEB_REPO:-https://github.com/dev-uros/vue-front-ai-setup.git}"
INFRA_REPO="${INFRA_REPO:-https://github.com/dev-uros/infra-ai-setup.git}"

# Offsets from the project's port base. One number per project, everything else
# derived from it -- there is no second list to keep in sync.
OFFSET_APP=0        # nginx (the API)
OFFSET_DB=1         # postgres
OFFSET_DB_TEST=2    # postgres-test
OFFSET_REDIS=3      # redis
OFFSET_GRAFANA=4    # grafana   (make observe)
OFFSET_ALLOY=5      # alloy     (make observe)
OFFSET_VITE=6       # vite dev server (the frontend)
PORT_SPAN=10        # ports reserved per project, so bases step by 10

PORT_BASE_START=8100
PORT_BASE_MAX=8900

name=""
port_base=""
parent_dir=""      # --dir, then $PROJECTS_DIR, then the prompt below
with_infra=1
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

    [name]              lowercase, digits and underscores: client_hub.
                        Asked for when omitted.

    --port-base N       first host port for this project (default: first free
                        block from 8100, stepping by 10)
    --dir PATH          where the project folder is created, asked for when
                        omitted. $PROJECTS_DIR sets the answer permanently;
                        the default is ~/Desktop/fg-projects
    --no-infra          skip the infra repo -- correct when this project will be
                        deployed onto a server that already runs it
    --setup             also build the containers, migrate and install the
                        frontend dependencies. Off by default: creating a
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

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)   usage; exit 0 ;;
        --port-base) port_base="${2:-}"; shift 2 ;;
        --dir)       parent_dir="${2:-}"; shift 2 ;;
        --no-infra)  with_infra=0; shift ;;
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

# Docker Compose accepts lowercase letters, digits, underscore and hyphen, and
# the name must start with a letter. An uppercase letter here fails much later,
# inside compose, with a message that does not mention this script.
name_ok() { printf '%s' "$1" | grep -qE '^[a-z][a-z0-9_-]*$'; }

while ! name_ok "$name"; do
    [ -z "$name" ] || say "'$name' will not do: lowercase letters, digits, _ and -, starting with a letter"
    # `|| die` rather than a bare read: on Ctrl-D read returns non-zero, and
    # under `set -e` that would end the script silently, mid-sentence.
    [ -t 0 ] || die "give a project name (lowercase letters, digits, _ and -)"
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

# --- port block --------------------------------------------------------------

# True when nothing is listening. Uses bash's own /dev/tcp so the script needs
# no nc, lsof or ss -- their flags differ between macOS and Linux.
port_free() {
    ! (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null
}

# Every port of the block has to be free AND unclaimed. Listening sockets are
# not enough on their own: a project that is merely stopped has no sockets, and
# handing its block to the next project is a collision that only shows up the
# day someone starts both.
block_free() {
    local base=$1 offset
    for offset in $OFFSET_APP $OFFSET_DB $OFFSET_DB_TEST $OFFSET_REDIS $OFFSET_GRAFANA $OFFSET_ALLOY $OFFSET_VITE; do
        port_free $((base + offset)) || return 1
    done
    ! printf '%s\n' "$claimed" | grep -qx "$base"
}

# Port bases of the projects already sitting next to this one. Their generated
# Makefile is the record -- there is no registry file to lose or to forget to
# update when a project is deleted.
claimed=$(grep -hE '^APP_PORT[[:space:]]*:=' "$parent_dir"/*/Makefile 2>/dev/null | tr -dc '0-9\n' || true)

if [ -n "$port_base" ]; then
    printf '%s' "$port_base" | grep -qE '^[0-9]+$' || die "--port-base must be a number"
    block_free "$port_base" || say "warning: ${port_base}-$((port_base + PORT_SPAN - 1)) is already listening or claimed by another project"
else
    port_base=""
    for candidate in $(seq $PORT_BASE_START $PORT_SPAN $PORT_BASE_MAX); do
        if block_free "$candidate"; then port_base=$candidate; break; fi
    done
    [ -n "$port_base" ] || die "no free port block between $PORT_BASE_START and $PORT_BASE_MAX -- pass --port-base"
fi

app_port=$((port_base + OFFSET_APP))
db_port=$((port_base + OFFSET_DB))
db_test_port=$((port_base + OFFSET_DB_TEST))
redis_port=$((port_base + OFFSET_REDIS))
grafana_port=$((port_base + OFFSET_GRAFANA))
alloy_port=$((port_base + OFFSET_ALLOY))
vite_port=$((port_base + OFFSET_VITE))

# --- target directory --------------------------------------------------------

# The root was checked and created above; $dir is absolute because $parent_dir
# is, and the name has already been proved free.
mkdir -p "$dir" || die "cannot create $dir"

# client_hub -> Client Hub
title=$(printf '%s' "$name" | tr '_-' '  ' | awk '{for (i = 1; i <= NF; i++) $i = toupper(substr($i, 1, 1)) substr($i, 2); print}')

printf '\n  %s  (%s)\n' "$title" "$name"
printf '  %s\n  ports %s-%s\n\n' "$dir" "$port_base" "$((port_base + PORT_SPAN - 1))"

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

say "writing api/.env"
cp "$dir/api/.env.example" "$dir/api/.env"

# The one line that renames every container, volume and image of this stack.
set_env COMPOSE_PROJECT_NAME "$name"                          "$dir/api/.env"
set_env APP_NAME             "\"$title\""                     "$dir/api/.env"
set_env APP_URL              "http://localhost:$app_port"      "$dir/api/.env"
# Where the emailed activation and reset links point, and the one origin CORS
# lets into the API from a browser.
set_env FRONTEND_URL         "http://localhost:$vite_port"     "$dir/api/.env"
set_env DB_DATABASE          "$name"                           "$dir/api/.env"
set_env DB_USERNAME          "$name"                           "$dir/api/.env"
set_env APP_PORT             "$app_port"                       "$dir/api/.env"
set_env FORWARD_DB_PORT      "$db_port"                        "$dir/api/.env"
set_env FORWARD_TEST_DB_PORT "$db_test_port"                   "$dir/api/.env"
set_env FORWARD_REDIS_PORT   "$redis_port"                     "$dir/api/.env"
set_env GRAFANA_PORT         "$grafana_port"                   "$dir/api/.env"
set_env ALLOY_PORT           "$alloy_port"                     "$dir/api/.env"

say "writing web/.env"
cp "$dir/web/.env.example" "$dir/web/.env"
# VITE_API_URL is the only VITE_ variable the frontend has, by its own rule.
# The dev server's port is not one -- it is passed on the command line, which
# is what `make web` in the generated Makefile does.
set_env VITE_API_URL "http://localhost:$app_port/api" "$dir/web/.env"

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

.PHONY: setup
setup: ## First run: build the images, boot, install deps, migrate
	@$(MAKE) -C api setup
	cd web && npm install

.PHONY: up
up: ## Start the API stack (postgres, redis, php, horizon, scheduler, nginx)
	@$(MAKE) -C api up

.PHONY: down
down: ## Stop the API stack (data volumes are kept)
	@$(MAKE) -C api down

.PHONY: web
web: ## Run the frontend dev server on this project's port
	cd web && npm run dev -- --port $(VITE_PORT) --strictPort

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
		| awk "BEGIN {FS = \":.*?## \"}; {printf \"  \033[36m%-10s\033[0m %s\n\", \$$1, \$$2}"
	@echo ""
MAKEFILE
} > "$dir/Makefile"

# --- first run ---------------------------------------------------------------

if [ "$run_setup" -eq 1 ] && ! command -v make >/dev/null; then
    say "make not found -- skipping the build"
    say "install make, then run: make -C \"$dir/api\" setup"
    run_setup=0
fi

if [ "$run_setup" -eq 1 ]; then
    printf '\n'
    say "building and booting the API (this takes a few minutes the first time)"
    printf '\n'
    make -C "$dir/api" setup

    if command -v npm >/dev/null; then
        printf '\n'
        say "installing frontend dependencies"
        (cd "$dir/web" && npm install --silent)
    else
        say "npm not found -- run 'npm install' in web/ yourself"
    fi
fi

# --- what to do next ---------------------------------------------------------

if [ "$run_setup" -eq 1 ]; then
    booted="    make ports          what is on which port
    make web            start the frontend"
else
    booted="    make setup          build and boot it (a few minutes, first time only)
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

  Containers are named ${name}-php-1, ${name}-postgres-1, and so on,
  so this project cannot collide with another one on this machine.

  None of the three folders is a git repository yet. When you have
  somewhere to push each one:

    cd api && git init && git add -A && git commit -m "Initial commit"
    git branch -M main && git remote add origin <url> && git push -u origin main

  Once it is up, create the first administrator:

    make -C api artisan c="admin:create you@example.com --name=... --surname=..."
  ------------------------------------------------------------------

NEXT
