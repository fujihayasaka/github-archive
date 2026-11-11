package secretscanning

import "github.com/github/sweagentd/internal/memory/core"

// ScanResponse represents the response from the secret scanning service.
type ScanResponse struct {
	NumBytesScanned uint64   `json:"numBytesScanned"`
	BlobsScanned    uint32   `json:"blobsScanned"`
	Secrets         []Secret `json:"secrets"`
}

// ToDomain converts the ScanResponse to a slice of core.MemorySecret domain objects.
func (r *ScanResponse) ToDomain(repoNwo core.RepoNWO) []core.MemorySecret {
	secrets := make([]core.MemorySecret, len(r.Secrets))
	for i, secret := range r.Secrets {
		secrets[i] = core.MemorySecret{
			ID:        core.NewMemoryID(),
			RepoNWO:   repoNwo,
			SecretKey: secret.Type.Type,
			Secret:    secret.Token,
		}
	}
	return secrets
}

// Secret represents a detected secret from the scanning service.
type Secret struct {
	Type       TokenType `json:"type"`
	Token      string    `json:"token"`
	TokenBytes []byte    `json:"tokenBytes"`
	Location   Location  `json:"location"`
}

// TokenType contains metadata about the type of secret token detected.
type TokenType struct {
	Type         string `json:"type"`
	Label        string `json:"label"`
	ProviderName string `json:"providerName"`
	Slug         string `json:"slug"`
	Confidence   string `json:"confidence"`
}

// Location describes where a secret was found within the scanned content.
type Location struct {
	FilePath    string `json:"filePath"`
	StartLine   uint   `json:"startLine"`
	EndLine     uint   `json:"endLine"`
	StartColumn uint   `json:"startColumn"`
	EndColumn   uint   `json:"endColumn"`
}
