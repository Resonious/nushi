// Package keychaintest is a keychain in memory for tests of the features
// that keep tokens in internal/keychain (Jira, GitHub).
package keychaintest

import (
	"errors"
	"sync"
)

// The fake's errors, which a test's keychain kinds (a feature's Keys) name.
var (
	ErrLocked  = errors.New("locked")
	ErrMissing = errors.New("not in the keychain")
)

// Keychain keeps items in memory, by account. Locked makes reads without
// a prompt fail with ErrLocked, as an earlier build's item does; Fail,
// when set, is every read's error.
type Keychain struct {
	mu     sync.Mutex
	Items  map[string]string
	Locked bool
	Fail   error
}

func (k *Keychain) Set(account, _ string, secret []byte) error {
	k.mu.Lock()
	defer k.mu.Unlock()
	if k.Items == nil {
		k.Items = map[string]string{}
	}
	k.Items[account] = string(secret)
	return nil
}

func (k *Keychain) Get(account string, prompt bool) ([]byte, error) {
	k.mu.Lock()
	defer k.mu.Unlock()
	if k.Locked && !prompt {
		return nil, ErrLocked
	}
	if k.Fail != nil {
		return nil, k.Fail
	}
	v, ok := k.Items[account]
	if !ok {
		return nil, ErrMissing
	}
	return []byte(v), nil
}

func (k *Keychain) Delete(account string) error {
	k.mu.Lock()
	defer k.mu.Unlock()
	delete(k.Items, account)
	return nil
}
