package codex

import (
	"os"
	"path/filepath"
	"runtime"
	"slices"
	"testing"

	"github.com/afrase/nushi/internal/testcheck"
)

// npmInstall lays out npm's global install of Codex under prefix, as on
// Unix (bin/codex a link to the package's codex.js) and Windows (a
// codex.cmd shim beside node_modules), with the platform's binary nested
// in the package, hoisted beside it or in the package itself; it says
// where the user's codex and the binary are.
func npmInstall(t *testing.T, layout string) (cli, binary string) {
	t.Helper()
	prefix, err := filepath.EvalSymlinks(t.TempDir()) // the Mac's /var is a link
	testcheck.NoErr(t, err)
	modules := filepath.Join(prefix, "lib", "node_modules")
	if runtime.GOOS == "windows" {
		modules = filepath.Join(prefix, "node_modules")
	}
	pkg := filepath.Join(modules, "@openai", "codex")
	testcheck.Write(t, filepath.Join(pkg, "bin", "codex.js"), "#!/usr/bin/env node\n")
	triple, platform := target()
	exe := "codex"
	if runtime.GOOS == "windows" {
		exe = "codex.exe"
	}
	vendor := filepath.Join("vendor", triple, "bin", exe)
	switch layout {
	case "nested":
		binary = filepath.Join(pkg, "node_modules", "@openai", platform, vendor)
	case "hoisted":
		binary = filepath.Join(modules, "@openai", platform, vendor)
	case "own":
		binary = filepath.Join(pkg, vendor)
	}
	if binary != "" {
		testcheck.Write(t, binary, "native")
		testcheck.NoErr(t, os.Chmod(binary, 0o755))
	}
	if runtime.GOOS == "windows" {
		cli = filepath.Join(prefix, "codex.cmd")
		testcheck.Write(t, cli, "@node \"%~dp0\\node_modules\\@openai\\codex\\bin\\codex.js\" %*\r\n")
		return cli, binary
	}
	cli = filepath.Join(prefix, "bin", "codex")
	testcheck.NoErr(t, os.MkdirAll(filepath.Dir(cli), 0o700))
	testcheck.NoErr(t, os.Symlink(filepath.Join("..", "lib", "node_modules", "@openai", "codex", "bin", "codex.js"), cli))
	return cli, binary
}

// npm's codex runs as its native binary wherever npm put it; without one
// it stays the launcher (which says what's missing), and a codex that
// isn't npm's is itself.
func TestNativeFindsNpmsBinary(t *testing.T) {
	if triple, _ := target(); triple == "" {
		t.Skip("Codex has no binary for this platform")
	}
	for _, layout := range []string{"nested", "hoisted", "own"} {
		t.Run(layout, func(t *testing.T) {
			cli, binary := npmInstall(t, layout)
			if got, _ := Native(cli); got != binary {
				t.Errorf("Native(%s) = %s, want %s", cli, got, binary)
			}
		})
	}
	t.Run("missing", func(t *testing.T) {
		cli, _ := npmInstall(t, "")
		if got, env := Native(cli); got != cli || env != nil {
			t.Errorf("Native = %s %q, want the launcher %s alone", got, env, cli)
		}
	})
	t.Run("not npm's", func(t *testing.T) {
		cli := filepath.Join(t.TempDir(), "codex")
		testcheck.Write(t, cli, "native")
		if got, env := Native(cli); got != cli || env != nil {
			t.Errorf("Native = %s %q, want %s alone", got, env, cli)
		}
	})
}

// A binary that can't run (no mode bit) isn't taken.
func TestNativeNeedsAProgram(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("Windows has no mode bit")
	}
	cli, binary := npmInstall(t, "nested")
	testcheck.NoErr(t, os.Chmod(binary, 0o644))
	if got, _ := Native(cli); got != cli {
		t.Errorf("Native = %s, want the launcher", got)
	}
}

// npm's binary gets what the launcher sets before it runs it: the
// package's real folder and npm as its manager, in place of any manager
// the environment already named; Codex reads them to tell how it was
// installed.
func TestNativeGetsTheLaunchersVariables(t *testing.T) {
	if triple, _ := target(); triple == "" {
		t.Skip("Codex has no binary for this platform")
	}
	cli, binary := npmInstall(t, "nested")
	pkg := filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(filepath.Dir(binary)))))))
	env := nativeEnv(cli, []string{"PATH=/bin", "CODEX_MANAGED_BY_BUN=1"})
	want := []string{"PATH=/bin", "CODEX_MANAGED_PACKAGE_ROOT=" + pkg, "CODEX_MANAGED_BY_NPM=1", "CODEX_PATH=" + binary}
	if !slices.Equal(env, want) {
		t.Errorf("env %q, want %q", env, want)
	}
}
