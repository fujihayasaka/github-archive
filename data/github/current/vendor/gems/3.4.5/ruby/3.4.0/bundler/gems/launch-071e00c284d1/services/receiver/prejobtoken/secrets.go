package prejobtoken

import (
	"context"

	errs "github.com/pkg/errors"

	"github.com/github/go-kvp"

	kredzpb "github.com/github/kredz/services/protobuf/credz"

	"github.com/github/launch/clients/earthsmoke"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild"
)

// GetEnvironmentSecrets returns an array of secrets for a given Environment
func GetEnvironmentSecrets(ctx context.Context, kredzClient kredz.Client, ghTwirpClient ghtwirp.Client, secretDecryptor earthsmoke.Decryptor, envID types.GlobalID, secretsAppID string, obs *observability.Observability) (map[string]string, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	nextEnvID, err := ghTwirpClient.GetNextGlobalID(ctx, envID.String())
	if err != nil {
		return nil, errs.Wrap(err, "error retrieving nextGlobalID for environment")
	}

	secretsAppNextGlobalID, err := ghTwirpClient.GetNextGlobalID(ctx, secretsAppID)
	if err != nil {
		return nil, errs.Wrap(err, "error retrieving nextGlobalID for secrets app")
	}

	envOwner := &kredzpb.CredentialOwner{
		Owner: &kredzpb.CredentialOwner_Environment{
			Environment: &kredzpb.Environment{
				GlobalId: nextEnvID.String(),
			},
		},
	}

	secretsForEnvironment, err := kredzClient.ListSecretsForOwner(ctx, envOwner, secretsAppNextGlobalID)
	if err != nil {
		return nil, errs.Wrap(err, "error retrieving secrets")
	}

	encSecrets := make(map[string]string)
	for key, secret := range secretsForEnvironment.Secrets {
		encSecrets[key] = secret
	}

	return getDecryptedEnvSecrets(ctx, encSecrets, nextEnvID, secretDecryptor, obs), nil
}

// Uses DietEarthsmoke to decrypt secrets. Decryption errors are returned, unlike getDecryptedEnvSecrets below.
func LocalDecryptSecrets(ctx context.Context, encSecrets map[string]string, secretScope string, secretDecryptor earthsmoke.Decryptor) (map[string]string, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	secrets := make(map[string]string)
	for key, secret := range encSecrets {
		decryptedValue, valid, err := secretDecryptor.DecryptSecretValue(ctx, secret, secretScope, workflowbuild.ActionsSecretSource)
		if err != nil {
			return nil, tracing.RecordError(span, errs.Wrap(err, "error locally decrypting secret"))
		}
		if !valid {
			return nil, tracing.RecordError(span, errs.New("secret is not valid"))
		}

		secrets[key] = decryptedValue
	}

	return secrets, nil
}

func getDecryptedEnvSecrets(ctx context.Context, encSecrets map[string]string, envID types.GlobalID, secretDecryptor earthsmoke.Decryptor, obs *observability.Observability) map[string]string {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	secretScope := envID.String()

	secrets := make(map[string]string)
	// For each secret we decrypt with both the legacy and next global ids of the
	// owners. If we encounter errors with decrypting the secret with the NextGlobalID
	// we report the same and return the Legacy value
	for key, secret := range encSecrets {
		decryptedValue, valid, err := secretDecryptor.DecryptSecretValue(ctx, secret, secretScope, workflowbuild.ActionsSecretSource)
		if err != nil {
			derr := errs.Wrap(err, "error decrypting secret")
			obs.Report(ctx, derr, kvp.String("gh.launch.environment.global_id", envID.String()))
			continue
		}
		if valid {
			secrets[key] = decryptedValue
		}
	}

	return secrets
}
