// Package agytrust says what a folder brings along for Antigravity CLI
// (agy 1.5.12; ADR 0031, docs/facts/agy.md) to run there. agy keeps no
// record of trusted folders, and loads a project's hooks and plugins
// without asking: in each folder from the repository's root down to the
// chat's (the folder alone outside a repository), under .agents, .agent,
// _agents and _agent: hooks.json, mcp_config.json, plugins/, plugins.json
// and skills.json (which can inherit or include external paths).
// Instructions (GEMINI.md, AGENTS.md, rules/, skills/) are left out, as
// Claude's and omp's cards leave them out.
package agytrust

import (
	"io/fs"
	"os"
	"path/filepath"

	"github.com/afrase/nushi/internal/folderfiles"
	"github.com/afrase/nushi/internal/git"
	"github.com/afrase/nushi/internal/model"
)

// Trust reads what a folder has Antigravity run.
type Trust struct{}

// Key is what "Start anyway" for agy is kept under (folderfiles.Key).
func (Trust) Key(folder string) string { return folderfiles.Key("agy", folder, files(folder)) }

// Trusted is false: agy keeps no folder trust record, and the trust
// feature looks for Start anyway's key itself.
func (Trust) Trusted(string, []string) (bool, error) { return false, nil }

// Runs shows every file agy loads code, hooks or plugin/MCP config from
// for folder.
func (Trust) Runs(folder string) ([]model.FolderRun, string, error) {
	fs := files(folder)
	var out []model.FolderRun
	for _, f := range fs {
		out = append(out, folderfiles.Run(f, "Loaded by Antigravity"))
	}
	return out, folderfiles.Key("agy", folder, fs), nil
}

var customizationDirs = []string{".agents", ".agent", "_agents", "_agent"}

func files(folder string) []folderfiles.File {
	resolved := git.RealPath(folder)
	top, _ := git.TrustRoot(resolved)
	dirs := []string{resolved}
	for dir := resolved; top != "" && dir != top && dir != filepath.Dir(dir); {
		dir = filepath.Dir(dir)
		dirs = append([]string{dir}, dirs...)
	}
	home, _ := os.UserHomeDir()
	home = git.RealPath(home)
	var roots []string
	for _, dir := range dirs {
		if dir == home {
			continue
		}
		for _, c := range customizationDirs {
			cdir := filepath.Join(dir, c)
			if fi, err := os.Lstat(cdir); err != nil {
				continue
			} else if fi.Mode()&fs.ModeSymlink != 0 { // agy follows it: can't vouch for it
				roots = append(roots, cdir)
				continue
			}
			for _, name := range []string{"hooks.json", "mcp_config.json", "plugins", "plugins.json", "skills.json"} {
				roots = append(roots, filepath.Join(cdir, name))
			}
		}
	}
	return folderfiles.Walk(roots, "agy")
}
