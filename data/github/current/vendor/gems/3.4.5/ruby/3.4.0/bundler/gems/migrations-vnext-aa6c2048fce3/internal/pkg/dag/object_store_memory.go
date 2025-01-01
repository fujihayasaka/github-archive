package dag

import (
	"context"
	"errors"
	"fmt"
	"sync"
)

// Enforce interface implementation
var _ ObjectStore = &MemoryObjectStore{}

// MemoryObjectStore in an in-memory implementation of the ObjectStore
// interface. This implementation should only be used for development
// and testing.
type MemoryObjectStore struct {
	store map[string][]byte
	mu    sync.Mutex
}

// NewMemoryObjectStore creates and returns a MemoryObjectStore.
func NewMemoryObjectStore() *MemoryObjectStore {
	return &MemoryObjectStore{
		store: make(map[string][]byte),
		mu:    sync.Mutex{},
	}
}

// GetPayload implements the GetPayload method of the ObjectStore interface.
func (m *MemoryObjectStore) GetPayload(_ context.Context, namespace, key string) ([]byte, error) {
	if namespace == "" {
		return nil, errors.New("namespace cannot be empty")
	}
	if key == "" {
		return nil, errors.New("key must not be empty")
	}
	key = fmt.Sprintf("%s/%s", namespace, key)

	m.mu.Lock()
	defer m.mu.Unlock()

	v, ok := m.store[key]
	if !ok {
		return nil, errors.New("key not found")
	}
	return v, nil
}

// WritePayload implements the WritePayload method of the ObjectStore interface.
func (m *MemoryObjectStore) WritePayload(_ context.Context, namespace, key string, payload []byte) error {
	if namespace == "" {
		return errors.New("namespace cannot be empty")
	}
	if key == "" {
		return errors.New("key must not be empty")
	}
	key = fmt.Sprintf("%s/%s", namespace, key)

	m.mu.Lock()
	defer m.mu.Unlock()
	m.store[key] = payload

	return nil
}
