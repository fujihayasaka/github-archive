package secretscanning

import (
	"context"

	"github.com/github/sweagentd/internal/memory/core"
)

// NoopSecretScanner is a no-op implementation of core.SecretScanner that
// always reports zero detected secrets. It is intended for development
// environments where the external secret-scanning service is not
// reachable and we want memory creation to succeed without depending on
// it.
type NoopSecretScanner struct{}

var _ core.SecretScanner = (*NoopSecretScanner)(nil)

// NewNoopSecretScanner returns a new NoopSecretScanner.
func NewNoopSecretScanner() *NoopSecretScanner {
	return &NoopSecretScanner{}
}

// Scan implements core.SecretScanner. It always returns no secrets and no
// error so that memory creation flows that gate on secret scanning are
// allowed to proceed.
func (s *NoopSecretScanner) Scan(_ context.Context, _ core.RepoNWO, _ *core.Memory) ([]core.MemorySecret, error) {
	return nil, nil
}
