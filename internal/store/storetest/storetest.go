// Package storetest is parts of internal/store in memory, for tests of the
// features that keep their state there.
package storetest

import (
	"encoding/json"
	"strings"
	"time"
)

// Answers is the store's cache of answers (store.Cache) in memory: Kept
// by area, name and key, each kept at the same time.
type Answers struct {
	Kept map[string]json.RawMessage
}

func (c *Answers) Cached(area, name, key string, v any) (time.Time, error) {
	d, ok := c.Kept[area+" "+name+" "+key]
	if !ok {
		return time.Time{}, nil
	}
	return time.Unix(1, 0), json.Unmarshal(d, v)
}

func (c *Answers) Cache(area, name, key string, v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	if c.Kept == nil {
		c.Kept = map[string]json.RawMessage{}
	}
	c.Kept[area+" "+name+" "+key] = data
	return nil
}

func (c *Answers) ForgetCache(area, name string) error {
	for k := range c.Kept {
		if strings.HasPrefix(k, area+" "+name+" ") {
			delete(c.Kept, k)
		}
	}
	return nil
}
