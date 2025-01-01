package aqueduct

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"os"
	"sync/atomic"
)

type producer interface {
	ID() string
	Sequence() uint64
}

type standardProducer struct{}

func (*standardProducer) ID() string       { return "" }
func (*standardProducer) Sequence() uint64 { return 0 }

type idempotentProducer struct {
	id       string
	sequence uint64
}

func (ip *idempotentProducer) ID() string { return ip.id }

func (ip *idempotentProducer) Sequence() uint64 {
	return atomic.AddUint64(&ip.sequence, 1)
}

// generateProducerID generates a random producer ID similar to
// aqueduct-client-ruby using the hostname and a random 10 byte hex value
// formatted as "hostname:random_hex".
func generateProducerID() (string, error) {
	name, err := os.Hostname()
	if err != nil {
		return "", fmt.Errorf("getting hostname: %w", err)
	}

	b := make([]byte, 10)
	_, err = rand.Read(b)
	if err != nil {
		return "", fmt.Errorf("reading random bytes: %w", err)
	}

	return name + ":" + hex.EncodeToString(b), nil
}
