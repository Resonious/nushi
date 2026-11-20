package claudehistory

import (
	"errors"
	"regexp"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

// A workflow's script opens with what the run is, as a JavaScript object
// literal: `export const meta = {name, description, phases: [{title,
// detail}]}` (docs/facts/claude.md). Its phases are the run's plan, so the
// app can show the phases not reached yet. The script is the model's text
// and isn't run: only that literal is read, as data (strings, numbers,
// booleans, arrays and objects); anything else in it (a call, a spread, a
// template's ${}) is no meta at all.

// scriptMeta is what a workflow's script says of itself.
type scriptMeta struct {
	Name, Description string
	Phases            []metaPhase
}

// metaPhase is a phase the script plans: its title and its line on it.
type metaPhase struct {
	Title, Detail string
}

var metaStart = regexp.MustCompile(`(?m)^\s*export\s+const\s+meta\s*=`)

// maxMetaDepth is how deep the literal may nest.
const maxMetaDepth = 16

var errNoMeta = errors.New("no meta literal")

// readMeta reads the meta literal of a workflow's script; an error says
// it has none that reads as plain data.
func readMeta(script string) (scriptMeta, error) {
	loc := metaStart.FindStringIndex(script)
	if loc == nil {
		return scriptMeta{}, errNoMeta
	}
	p := &literal{s: script[loc[1]:]}
	v, err := p.value(0)
	if err != nil {
		return scriptMeta{}, err
	}
	obj, ok := v.(map[string]any)
	if !ok {
		return scriptMeta{}, errNoMeta
	}
	var m scriptMeta
	m.Name, _ = obj["name"].(string)
	m.Description, _ = obj["description"].(string)
	phases, _ := obj["phases"].([]any)
	for _, ph := range phases {
		o, _ := ph.(map[string]any)
		title, _ := o["title"].(string)
		if strings.TrimSpace(title) == "" {
			continue
		}
		detail, _ := o["detail"].(string)
		m.Phases = append(m.Phases, metaPhase{Title: title, Detail: detail})
	}
	return m, nil
}

// literal reads a JavaScript literal from s, from its start.
type literal struct {
	s string
	i int
}

// space skips blanks and comments.
func (p *literal) space() {
	for p.i < len(p.s) {
		switch {
		case strings.HasPrefix(p.s[p.i:], "//"):
			if j := strings.IndexByte(p.s[p.i:], '\n'); j >= 0 {
				p.i += j + 1
			} else {
				p.i = len(p.s)
			}
		case strings.HasPrefix(p.s[p.i:], "/*"):
			if j := strings.Index(p.s[p.i+2:], "*/"); j >= 0 {
				p.i += j + 4
			} else {
				p.i = len(p.s)
			}
		default:
			r, n := utf8.DecodeRuneInString(p.s[p.i:])
			if !unicode.IsSpace(r) {
				return
			}
			p.i += n
		}
	}
}

// peek is the next byte past blanks, 0 at the end.
func (p *literal) peek() byte {
	p.space()
	if p.i >= len(p.s) {
		return 0
	}
	return p.s[p.i]
}

func (p *literal) value(depth int) (any, error) {
	if depth > maxMetaDepth {
		return nil, errNoMeta
	}
	switch c := p.peek(); {
	case c == '{':
		return p.object(depth)
	case c == '[':
		return p.array(depth)
	case c == '\'' || c == '"' || c == '`':
		return p.str()
	case c == '-' || c == '.' || c >= '0' && c <= '9':
		return p.number()
	default:
		switch p.ident() {
		case "true":
			return true, nil
		case "false":
			return false, nil
		case "null", "undefined":
			return nil, nil
		}
		return nil, errNoMeta
	}
}

func (p *literal) object(depth int) (map[string]any, error) {
	p.i++ // {
	obj := map[string]any{}
	for {
		var key string
		switch c := p.peek(); {
		case c == '}':
			p.i++
			return obj, nil
		case c == '\'' || c == '"':
			k, err := p.str()
			if err != nil {
				return nil, err
			}
			key = k
		default:
			if key = p.ident(); key == "" {
				return nil, errNoMeta // a computed key, a spread, a method
			}
		}
		if p.peek() != ':' {
			return nil, errNoMeta // a shorthand names a variable
		}
		p.i++
		v, err := p.value(depth + 1)
		if err != nil {
			return nil, err
		}
		obj[key] = v
		switch p.peek() {
		case ',':
			p.i++
		case '}':
		default:
			return nil, errNoMeta
		}
	}
}

func (p *literal) array(depth int) ([]any, error) {
	p.i++ // [
	var list []any
	for {
		if p.peek() == ']' {
			p.i++
			return list, nil
		}
		v, err := p.value(depth + 1)
		if err != nil {
			return nil, err
		}
		list = append(list, v)
		switch p.peek() {
		case ',':
			p.i++
		case ']':
		default:
			return nil, errNoMeta
		}
	}
}

// ident reads a name: letters, digits, _ and $; "" when none is there.
func (p *literal) ident() string {
	p.space()
	start := p.i
	for p.i < len(p.s) {
		r, n := utf8.DecodeRuneInString(p.s[p.i:])
		if r != '_' && r != '$' && !unicode.IsLetter(r) && (p.i == start || !unicode.IsDigit(r)) {
			break
		}
		p.i += n
	}
	return p.s[start:p.i]
}

func (p *literal) number() (float64, error) {
	start := p.i
	for p.i < len(p.s) && strings.IndexByte("0123456789+-.eExXabcdefABCDEF_", p.s[p.i]) >= 0 {
		p.i++
	}
	text := strings.ReplaceAll(p.s[start:p.i], "_", "")
	if f, err := strconv.ParseFloat(text, 64); err == nil {
		return f, nil
	}
	if n, err := strconv.ParseInt(text, 0, 64); err == nil { // 0x10, 0o7, 0b1
		return float64(n), nil
	}
	return 0, errNoMeta
}

// str reads a quoted string, or a template without substitutions.
func (p *literal) str() (string, error) {
	quote := p.s[p.i]
	p.i++
	var b strings.Builder
	for p.i < len(p.s) {
		c := p.s[p.i]
		switch {
		case c == quote:
			p.i++
			return b.String(), nil
		case c == '\n' && quote != '`':
			return "", errNoMeta
		case c == '$' && quote == '`' && strings.HasPrefix(p.s[p.i:], "${"):
			return "", errNoMeta // a substitution: code
		case c == '\\':
			if err := p.escape(&b); err != nil {
				return "", err
			}
		default:
			b.WriteByte(c)
			p.i++
		}
	}
	return "", errNoMeta
}

// escape reads one escape at p.i, its backslash.
func (p *literal) escape(b *strings.Builder) error {
	p.i++
	if p.i >= len(p.s) {
		return errNoMeta
	}
	c := p.s[p.i]
	p.i++
	switch c {
	case 'n':
		b.WriteByte('\n')
	case 't':
		b.WriteByte('\t')
	case 'r':
		b.WriteByte('\r')
	case 'b', 'f', 'v', '0':
	case '\n': // a line continued
	case 'u':
		hex := ""
		if strings.HasPrefix(p.s[p.i:], "{") {
			end := strings.IndexByte(p.s[p.i:], '}')
			if end < 0 {
				return errNoMeta
			}
			hex, p.i = p.s[p.i+1:p.i+end], p.i+end+1
		} else if p.i+4 <= len(p.s) {
			hex, p.i = p.s[p.i:p.i+4], p.i+4
		}
		r, err := strconv.ParseUint(hex, 16, 32)
		if err != nil {
			return errNoMeta
		}
		b.WriteRune(rune(r))
	case 'x':
		if p.i+2 > len(p.s) {
			return errNoMeta
		}
		r, err := strconv.ParseUint(p.s[p.i:p.i+2], 16, 8)
		if err != nil {
			return errNoMeta
		}
		p.i += 2
		b.WriteRune(rune(r))
	default:
		b.WriteByte(c)
	}
	return nil
}
