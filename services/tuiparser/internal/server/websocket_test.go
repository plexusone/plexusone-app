package server

import (
	"sync"
	"testing"
)

func TestTrySendAfterClose(t *testing.T) {
	c := &Client{send: make(chan []byte, 1)}

	if !c.trySend([]byte("a")) {
		t.Fatal("trySend on an open client with room returned false")
	}
	if c.trySend([]byte("b")) {
		t.Error("trySend on a full buffer returned true")
	}

	c.closeSend()
	c.closeSend() // a second close must not panic

	if c.trySend([]byte("c")) {
		t.Error("trySend after close returned true")
	}

	// The message queued before close is still delivered, then the channel ends.
	if msg, ok := <-c.send; !ok || string(msg) != "a" {
		t.Errorf("got %q, %v; want \"a\", true", msg, ok)
	}
	if _, ok := <-c.send; ok {
		t.Error("send channel still open after closeSend")
	}
}

// TestTrySendConcurrentClose races senders against the hub closing the
// channel; before trySend this could panic with "send on closed channel".
func TestTrySendConcurrentClose(t *testing.T) {
	for i := 0; i < 100; i++ {
		c := &Client{send: make(chan []byte, 256)}
		var wg sync.WaitGroup
		for j := 0; j < 4; j++ {
			wg.Add(1)
			go func() {
				defer wg.Done()
				for k := 0; k < 50; k++ {
					c.trySend([]byte("x"))
				}
			}()
		}
		c.closeSend()
		wg.Wait()
	}
}
