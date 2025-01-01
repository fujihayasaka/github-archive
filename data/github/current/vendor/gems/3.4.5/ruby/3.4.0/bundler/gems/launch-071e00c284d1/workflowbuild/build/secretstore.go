package build

import (
	"context"

	"github.com/github/launch/workflowbuild"
)

// EncryptedSecret
type EncryptedSecret struct {
	// Value is the base64-encoded encrypted value
	Value string
	// Scope is the GlobalID of the owner of the secret (an org, repo or environment)
	Scope string
}

// SecretStore is an interface for application scoped secrets, namely Actions and Dependabot. Historically, secrets are obtained on a best effort basis.
// Secrets are handled within Launch using the `diet_earthsmoke` module
// See workflowbuild.SecretSource for the current list of sources.
type SecretStore interface {
	// GetDecryptedSecrets returns a map secret names to decrypted secret values for the given secret source. The caller should re-encrypt the value as soon as possible.
	GetDecryptedSecrets(ctx context.Context) map[string]string

	// GetEncryptedSecrets returns a map of secret names to encrypted secret value
	GetEncryptedSecrets() map[string]EncryptedSecret

	// GetSecretSource returns the workflowbuild.SecretSource that this SecretStore is associated with.
	GetSecretSource() workflowbuild.SecretSource
}
