package secretscanning

import "github.com/github/sweagentd/internal/memory/core"

type ScanResponse struct {
	NumBytesScanned uint64   `json:"numBytesScanned"`
	BlobsScanned    uint32   `json:"blobsScanned"`
	Secrets         []Secret `json:"secrets"`
}

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

type Secret struct {
	Type       TokenType `json:"type"`
	Token      string    `json:"token"`
	TokenBytes []byte    `json:"tokenBytes"`
	Location   Location  `json:"location"`
}

type TokenType struct {
	Type         string `json:"type"`
	Label        string `json:"label"`
	ProviderName string `json:"providerName"`
	Slug         string `json:"slug"`
	Confidence   string `json:"confidence"`
}

type Location struct {
	FilePath    string `json:"filePath"`
	StartLine   uint   `json:"startLine"`
	EndLine     uint   `json:"endLine"`
	StartColumn uint   `json:"startColumn"`
	EndColumn   uint   `json:"endColumn"`
}
