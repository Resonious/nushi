// Package agyskills reads the skills Antigravity CLI (agy 1.5.12;
// docs/facts/agy.md) uses in a folder:
//   - in the folder and each folder above it, up to the repository's root
//     (outside git, up to your home folder, never it): .agents/skills
//     ("shared") and .agent/skills, _agents/skills, _agent/skills
//     ("project");
//   - yours: ~/.gemini/config/skills ("user");
//   - no trust: a folder's skills load without asking;
//   - the first folder that has a name wins (nearest project dir first,
//     then global).
//
// agy has no per-skill switch for discovered skills (NoSwitch); Trash
// moves a skill folder right in agy's own places (.agent/skills,
// _agents/skills, _agent/skills, ~/.gemini/config/skills). Nushi leaves
// linked project roots out (ADR 0052's rule). Built-in skills, plugins'
// skills and skills.json entries aren't listed. Nothing here runs agy.
package agyskills

import (
	"cmp"
	"context"
	"errors"
	"os"
	"path/filepath"

	"github.com/afrase/nushi/internal/agy"
	"github.com/afrase/nushi/internal/git"
	"github.com/afrase/nushi/internal/model"
	"github.com/afrase/nushi/internal/skillfile"
)

// Agy reads Antigravity's skills.
type Agy struct{}

const noSwitch = "Antigravity has no per-skill switch; delete a skill's folder to remove it."

type root struct {
	path, source string
}

// walk is folder and the folders above it agy reads, nearest first,
// stopping at the repository's root (or outside git, before home).
func walk(folder string) []string {
	home, _ := os.UserHomeDir()
	home = git.RealPath(home)
	top := skillfile.Top(folder)
	var out []string
	for dir := folder; dir != home; dir = filepath.Dir(dir) {
		out = append(out, dir)
		if dir == top || dir == filepath.Dir(dir) {
			break
		}
	}
	return out
}

// projectRoots are the customization roots agy scans in a workspace, in
// priority order.
var projectRoots = []struct {
	rel, source string
}{
	{".agents/skills", "shared"},
	{".agent/skills", "project"},
	{"_agents/skills", "project"},
	{"_agent/skills", "project"},
}

// roots are the skills folders agy reads for folder, the winner of a name
// first.
func roots(folder string) []root {
	home, _ := os.UserHomeDir()
	var out []root
	for _, d := range walk(folder) {
		for _, r := range projectRoots {
			if !skillfile.Linked(d, r.rel) {
				out = append(out, root{path: filepath.Join(d, filepath.FromSlash(r.rel)), source: r.source})
			}
		}
	}
	return append(out, root{path: filepath.Join(agy.ConfigDir(home), "skills"), source: "user"})
}

// List returns Antigravity's skills in folder, the shared ones among them.
func (Agy) List(_ context.Context, folder string) (model.Skills, error) {
	out := model.Skills{ReadsShared: true, NoSwitch: noSwitch}
	folder = git.RealPath(folder)
	seen := map[string]bool{}
	for _, r := range roots(folder) {
		for _, f := range skillfile.List(r.path) {
			name := cmp.Or(f.Name, f.Entry)
			if seen[name] {
				continue
			}
			seen[name] = true
			out.Skills = append(out.Skills, model.Skill{
				Name:        name,
				Description: f.Description,
				Source:      r.source,
				Path:        f.Dir,
				Linked:      f.Linked,
				State:       "on",
				Tokens:      skillfile.Tokens(name + f.Description),
			})
		}
	}
	return out, nil
}

// SetSkillOn refuses: Antigravity has no per-skill switch for discovered
// skills.
func (Agy) SetSkillOn(context.Context, string, string, string, bool) error {
	return errors.New(noSwitch)
}

// own are the places agy's own skill folders are in (not .agents/skills,
// which is shared and trashed by features/skills).
func own(folder string) (project, yours []string) {
	home, _ := os.UserHomeDir()
	for _, d := range walk(git.RealPath(folder)) {
		for _, rel := range []string{".agent/skills", "_agents/skills", "_agent/skills"} {
			if !skillfile.Linked(d, rel) {
				project = append(project, filepath.Join(d, filepath.FromSlash(rel)))
			}
		}
	}
	return project, []string{filepath.Join(agy.ConfigDir(home), "skills")}
}

// CanTrash says why Trash wouldn't move path: nil only for a skill's
// folder right in one of agy's own places.
func (Agy) CanTrash(_ context.Context, folder, path string) error {
	project, yours := own(folder)
	return skillfile.CanTrash(project, yours, path)
}

// Trash moves one of agy's own skill folders to the Trash: only one
// CanTrash passes.
func (Agy) Trash(ctx context.Context, folder, path string) error {
	project, yours := own(folder)
	return skillfile.Trash(ctx, project, yours, path)
}
