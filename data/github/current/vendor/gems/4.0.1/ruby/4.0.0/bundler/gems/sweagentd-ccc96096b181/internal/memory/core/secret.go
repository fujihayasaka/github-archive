package core

import "context"

// MemorySecret represents a secret that is stored in a memory
// If a secret is not found, it will trigger an error in the memory service
type MemorySecret struct {
	ID        MemoryID `json:"id"`
	RepoNWO   RepoNWO  `json:"repo_nwo"`
	SecretKey string   `json:"secret_key"`
	Secret    string   `json:"secret"`
}

// SecretScanner defines the interface for scanning memory content for secrets.
type SecretScanner interface {
	Scan(ctx context.Context, repoNWO RepoNWO, memory Memory) ([]MemorySecret, error)
}
