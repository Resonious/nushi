package worker_test

import (
	"bytes"
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"io"
	"os"
	"testing"

	"github.com/afrase/nushi/internal/testcheck"
	"github.com/afrase/nushi/noiseconn"
	"github.com/afrase/nushi/relay"
)

// TestWorkerPair runs the daemon's relay and Noise clients against a Worker
// with throwaway keys. Set NUSHI_WORKER_TEST_URL to a running relay.
func TestWorkerPair(t *testing.T) {
	url := os.Getenv("NUSHI_WORKER_TEST_URL")
	if url == "" {
		t.Skip("set NUSHI_WORKER_TEST_URL to test a running Worker")
	}
	pub, key, err := ed25519.GenerateKey(rand.Reader)
	testcheck.NoErr(t, err)
	var d relay.Dialer
	listener, err := d.Listen(t.Context(), url, key)
	testcheck.NoErr(t, err)
	t.Cleanup(func() { _ = listener.Close() })
	phone, err := d.Dial(t.Context(), url, relay.ListenID(pub))
	testcheck.NoErr(t, err)
	t.Cleanup(func() { _ = phone.Close() })
	macKey, err := noiseconn.NewKey()
	testcheck.NoErr(t, err)
	phoneKey, err := noiseconn.NewKey()
	testcheck.NoErr(t, err)
	done := make(chan error, 1)
	go func() {
		mac, err := noiseconn.Respond(listener, noiseconn.Config{Static: macKey}, func(peer []byte) error {
			if !bytes.Equal(peer, phoneKey.Public) {
				return errors.New("unexpected phone key")
			}
			return nil
		})
		if err == nil {
			_, err = mac.Write([]byte("paired"))
		}
		done <- err
	}()
	conn, err := noiseconn.Initiate(phone, noiseconn.Config{Static: phoneKey}, macKey.Public)
	testcheck.NoErr(t, err)
	answer := make([]byte, len("paired"))
	_, err = io.ReadFull(conn, answer)
	testcheck.NoErr(t, err)
	testcheck.NoErr(t, <-done)
	if string(answer) != "paired" {
		t.Fatal("wrong answer from daemon")
	}
}
