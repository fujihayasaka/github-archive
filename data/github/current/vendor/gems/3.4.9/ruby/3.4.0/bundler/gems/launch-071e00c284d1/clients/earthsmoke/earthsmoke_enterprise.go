package earthsmoke

import (
	"context"
	"encoding/base64"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/workflowbuild"
)

// NewEnterpriseDecryptor is the decryptor
// used within a GHES instance for secrets
func NewEnterpriseDecryptor() Decryptor {
	return &enterpriseDecryptor{}
}

type enterpriseDecryptor struct {
}

// DecryptSecretValue just returns the secret value, it doesn't actually
// decrypt because it is stored in plaintext.
func (d *enterpriseDecryptor) DecryptSecretValue(ctx context.Context, secretValue, _ string, _ workflowbuild.SecretSource) (string, bool, error) {
	_, span := tracing.Start(ctx)
	defer span.End()

	raw, err := base64.StdEncoding.DecodeString(secretValue)
	if err != nil {
		return "", false, err
	}

	return string(raw), true, nil
}

func (d *enterpriseDecryptor) LocalDecryptSecretValue(ctx context.Context, secretValue, scope string, source workflowbuild.SecretSource) (string, bool, error) {
	// call the implementation above.
	return d.DecryptSecretValue(ctx, secretValue, scope, source)
}
