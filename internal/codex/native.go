package codex

import (
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"strings"
)

// Native is the program behind cli, the user's codex, and the variables
// to run it with: npm's codex is a Node script (@openai/codex's
// bin/codex.js, about 14 MB of Node a run) that finds the native binary
// its platform package holds and runs it with CODEX_MANAGED_PACKAGE_ROOT
// (the package's real folder) and CODEX_MANAGED_BY_NPM set, which Codex
// reads to tell how it was installed (docs/facts/codex.md). Native finds
// that binary as the script does and gives the same variables, so Codex
// runs without Node and sees the install the launcher would have shown it;
// the launcher's guess at bun, pnpm or Vite+ owning the install isn't
// repeated: those say npm. For a codex that is no npm install (Homebrew's,
// a standalone one) it is cli and no variables. The native binary finds
// its own files (codex-path/rg, codex-package.json) beside itself.
func Native(cli string) (path string, env []string) {
	pkg := npmPackage(cli)
	if pkg == "" {
		return cli, nil
	}
	triple, platform := target()
	if triple == "" {
		return cli, nil
	}
	exe := "codex"
	if runtime.GOOS == "windows" {
		exe = "codex.exe"
	}
	root, err := filepath.EvalSymlinks(pkg)
	if err != nil {
		return cli, nil
	}
	vendor := filepath.Join("vendor", triple, "bin", exe)
	for _, dir := range []string{
		filepath.Join(pkg, "node_modules", "@openai", platform), // npm's nesting
		filepath.Join(filepath.Dir(pkg), platform),              // hoisted beside it
		pkg, // an older package that carried every platform's
	} {
		if p := filepath.Join(dir, vendor); isProgram(p) {
			return p, []string{"CODEX_MANAGED_PACKAGE_ROOT=" + root, "CODEX_MANAGED_BY_NPM=1"}
		}
	}
	return cli, nil
}

// managedBy are the launcher's variables naming the package manager that
// installed Codex; it clears them all before it sets its own.
var managedBy = []string{"CODEX_MANAGED_BY_NPM", "CODEX_MANAGED_BY_BUN", "CODEX_MANAGED_BY_PNPM", "CODEX_MANAGED_BY_VITE_PLUS"}

// nativeEnv is env to run cli in as Native's program: with the launcher's
// variables when it is npm's binary, any managedBy env already had left
// out as the launcher leaves them out, and CODEX_PATH naming it.
func nativeEnv(cli string, env []string) []string {
	path, vars := Native(cli)
	out := slices.Clone(env)
	if vars != nil {
		out = slices.DeleteFunc(out, func(kv string) bool {
			name, _, _ := strings.Cut(kv, "=")
			return slices.Contains(managedBy, name)
		})
		out = append(out, vars...)
	}
	return append(out, "CODEX_PATH="+path)
}

func npmPackage(cli string) string {
	if script, err := filepath.EvalSymlinks(cli); err == nil && filepath.Base(script) == "codex.js" &&
		filepath.Base(filepath.Dir(script)) == "bin" {
		return filepath.Dir(filepath.Dir(script))
	}
	pkg := filepath.Join(filepath.Dir(cli), "node_modules", "@openai", "codex")
	if st, err := os.Stat(filepath.Join(pkg, "bin", "codex.js")); err == nil && st.Mode().IsRegular() {
		return pkg
	}
	return ""
}

// target is the Rust target triple and npm platform package of Codex's
// binary for this platform, as bin/codex.js names them; "" for a
// platform Codex has no binary for.
func target() (triple, platform string) {
	switch runtime.GOOS + "/" + runtime.GOARCH {
	case "darwin/arm64":
		return "aarch64-apple-darwin", "codex-darwin-arm64"
	case "darwin/amd64":
		return "x86_64-apple-darwin", "codex-darwin-x64"
	case "linux/amd64":
		return "x86_64-unknown-linux-musl", "codex-linux-x64"
	case "linux/arm64":
		return "aarch64-unknown-linux-musl", "codex-linux-arm64"
	case "windows/amd64":
		return "x86_64-pc-windows-msvc", "codex-win32-x64"
	case "windows/arm64":
		return "aarch64-pc-windows-msvc", "codex-win32-arm64"
	}
	return "", ""
}

// isProgram says p is a regular file one can run (on Windows, any
// regular file: there's no mode bit).
func isProgram(p string) bool {
	st, err := os.Stat(p)
	if err != nil || !st.Mode().IsRegular() {
		return false
	}
	return runtime.GOOS == "windows" || st.Mode()&0o111 != 0
}
