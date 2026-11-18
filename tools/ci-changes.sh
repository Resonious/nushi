#!/bin/sh
# What a change can affect, for CI's jobs to skip what it can't (ADR 0129):
# go=true when Go's jobs must run, app=true when the app's must, code=true
# when either, one per line for $GITHUB_OUTPUT.
#
#   tools/ci-changes.sh <event> <base> <head>
#   tools/ci-changes.sh --self-test
#
# A pull request's change is its whole branch (from its merge base with the
# base), a push's what it pushed (before..after). Anything else runs
# everything: another event (the release's call, a run by hand), a push
# that made its branch or rewrote it, no change at all, or any error.
#
# Docs (docs/, the root's Markdown, LICENSE) are read by no build or test;
# a Markdown file anywhere else counts by its folder. Go's folders mark go,
# the app's and the Dart packages' app (app/windows too, which only the
# Windows app's build reads); app/macos marks both, because the window's
# Swift tests run in Go's macOS lint job. Anything else (CI, the
# Makefile, tools, protos, packaging, a path not named here) marks both.
set -u

# kinds reads paths, one a line, and prints "<go> <app>".
kinds() {
	go=false
	app=false
	while IFS= read -r path; do
		case $path in
		"" | docs/* | LICENSE) continue ;;
		*/*) ;;
		*.md) continue ;;
		esac
		case $path in
		cmd/* | internal/* | relay/* | noiseconn/* | go.mod | go.sum | .golangci.yml) go=true ;;
		app/macos/*) go=true app=true ;;
		app/* | packages/* | analysis_options.yaml) app=true ;;
		*) go=true app=true ;;
		esac
	done
	echo "$go $app"
}

# say prints the outputs for go and app.
say() {
	echo "go=$1"
	echo "app=$2"
	if [ "$1" = true ] || [ "$2" = true ]; then echo "code=true"; else echo "code=false"; fi
}

# everything is the safe answer, with why on stderr (the job's log).
everything() {
	echo "ci-changes: everything runs: $1" >&2
	say true true
	exit 0
}

self_test() {
	failed=0
	check() { # <want> <paths, one a line>
		got=$(printf '%s\n' "$2" | kinds)
		if [ "$got" != "$1" ]; then
			echo "ci-changes: $(printf '%s' "$2" | tr '\n' ' '): got $got, want $1" >&2
			failed=1
		fi
	}
	check "false false" "docs/adr/0129-x.md"
	check "false false" "README.md"
	check "false false" "AGENTS.md
CLAUDE.md
LICENSE"
	check "false true" "app/README.md"
	check "true false" "internal/git/git.go"
	check "true false" "cmd/nushid/main.go"
	check "true false" "go.sum"
	check "true false" "relay/relay.go
docs/remote.md"
	check "false true" "app/lib/chat_view.dart"
	check "false true" "app/test/timings.tsv"
	check "false true" "packages/noise/lib/noise.dart"
	check "false true" "app/windows/runner/web_views.cpp"
	check "false true" "app/windows/runner/CMakeLists.txt"
	check "true true" "app/macos/Runner/Placement.swift"
	check "true true" ".github/workflows/ci.yml"
	check "true true" "Makefile"
	check "true true" "tools/test-shards/main.go"
	check "true true" "proto/nushi/v1/nushi.proto"
	check "true true" "packaging/homebrew/nushi.rb"
	check "true true" "somewhere/new"
	check "true true" "internal/x.go
app/lib/x.dart"
	check "false false" ""
	for args in "workflow_dispatch a b" "release a b" "push 0000000000000000000000000000000000000000 HEAD" "push '' HEAD" "push deadbeefdeadbeef HEAD" "pull_request deadbeefdeadbeef HEAD" "push HEAD HEAD"; do
		got=$(eval "main $args" 2>/dev/null | tr '\n' ' ')
		if [ "$got" != "go=true app=true code=true " ]; then
			echo "ci-changes: $args: got $got, want everything" >&2
			failed=1
		fi
	done
	if [ "$failed" = 0 ]; then echo "ci-changes: self-test ok"; fi
	return "$failed"
}

main() {
	event=$1 base=$2 head=$3
	case $event in
	push | pull_request) ;;
	*) everything "event $event" ;;
	esac
	case $base in
	"" | *[!0]*) ;;
	*) everything "a new branch" ;;
	esac
	[ -n "$base" ] || everything "no base"
	if [ "$event" = pull_request ]; then
		base=$(git merge-base "$base" "$head") || everything "no merge base"
	fi
	# Names only, no renames: a rename's two paths both count, and no blob is fetched.
	paths=$(git diff --no-renames --name-only "$base" "$head") || everything "no diff from $base"
	[ -n "$paths" ] || everything "no change"
	echo "ci-changes: $(printf '%s\n' "$paths" | wc -l | tr -d ' ') paths from $(printf %.12s "$base") to $(printf %.12s "$head")" >&2
	# shellcheck disable=SC2046 # kinds prints two words
	say $(printf '%s\n' "$paths" | kinds)
}

if [ "${1-}" = --self-test ]; then
	self_test
	exit
fi
[ $# = 3 ] || {
	echo "usage: tools/ci-changes.sh <event> <base> <head> | --self-test" >&2
	exit 2
}
main "$@"
