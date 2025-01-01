package workflowinvoker

import (
	"context"

	errs "github.com/pkg/errors"

	"github.com/github/go-kvp"

	"github.com/github/launch/clients/earthsmoke"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/kredz"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild"
	"github.com/github/launch/workflowbuild/build"
)

type secretStore struct {
	secretSource        workflowbuild.SecretSource
	repoID              types.GlobalID
	encryptedSecretsMap map[string]build.EncryptedSecret
	secretDecryptor     earthsmoke.Decryptor
	log                 logger.Logger
}

func newSecretStore(
	ctx context.Context,
	kredzClient kredz.Client,
	ghTwirpClient ghtwirp.Client,
	secretDecryptor earthsmoke.Decryptor,
	data *types.WorkflowInvocationData,
	repoID types.GlobalID,
	secretsAppID string,
	secretSource workflowbuild.SecretSource,
	log logger.Logger,
) (build.SecretStore, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	repoNextGlobalID, err := ghTwirpClient.GetNextGlobalID(ctx, repoID.String())
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	orgNextGlobalID, err := ghTwirpClient.GetNextGlobalID(ctx, data.Owner.GlobalID.String())
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	secretAppNextGlobalID, err := ghTwirpClient.GetNextGlobalID(ctx, secretsAppID)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	secretsForRepository, err := kredzClient.ListSecretsForRepository(ctx, data.Owner.Type, orgNextGlobalID, repoNextGlobalID, data.RepoIsPrivate, secretAppNextGlobalID)
	if err != nil {
		return nil, errs.Wrap(err, "error retrieving secrets")
	}
	encryptedSecretsMap := make(map[string]build.EncryptedSecret)
	for key, repoSecret := range secretsForRepository.RepositorySecrets {
		encryptedSecretsMap[key] = build.EncryptedSecret{
			Value: repoSecret,
			Scope: repoNextGlobalID.String(),
		}
	}

	if canUseOrgSecrets(data, secretSource) {
		// Merge
		for key, orgSecret := range secretsForRepository.OrganizationSecrets {
			if _, ok := encryptedSecretsMap[key]; !ok {
				// Repo doesn't have a secret with that key, take org one
				encryptedSecretsMap[key] = build.EncryptedSecret{
					Value: orgSecret,
					Scope: orgNextGlobalID.String(),
				}
			}
		}
	}

	return &secretStore{
		secretSource:        secretSource,
		repoID:              repoID,
		encryptedSecretsMap: encryptedSecretsMap,
		secretDecryptor:     secretDecryptor,
		log:                 log,
	}, nil
}

// GetDecryptedSecrets returns a map of secret names to decrypted secret values on a best effort basis.
// If there is a problem decrypting a secret, the error will be logged
// and any problematic secret will be omitted from the return value.
func (s *secretStore) GetDecryptedSecrets(ctx context.Context) map[string]string {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	secretsMap := make(map[string]string)
	for key, secret := range s.encryptedSecretsMap {
		decryptedValue, valid, err := s.secretDecryptor.DecryptSecretValue(ctx, secret.Value, secret.Scope, s.secretSource)
		if err != nil {
			// Historically, secret _names_ were not validated in the clients. Once this was added
			// the only user errors that should be seen here are those were the user did not encrypt
			// the secret value properly when creating secrets via the API.
			// Since secret decryption is done locally, this isn't expected to intermittently fail for the same secret.
			//
			// One unfortunate drawback of this approach is that we do not inform the user of problems with their
			// secrets. They will appear as blank secrets and may result in customer support tickets. Though
			// this seems rare enough to be acceptable.
			//
			// See PR that added name validation to the clients: https://github.com/github/github/pull/139454
			s.log.Error(ctx, "error decrypting secret",
				kvp.Err(err),
				kvp.String("gh.repo.global_id", s.repoID.String()),
			)
			continue
		}

		if valid {
			secretsMap[key] = decryptedValue
		} else {
			s.log.Log(ctx, "non valid secret", kvp.String("gh.repo.global_id", s.repoID.String()))
		}
	}

	return secretsMap
}

// GetEncryptedSecrets returns a map of secret names to encrypted secret value
func (s *secretStore) GetEncryptedSecrets() map[string]build.EncryptedSecret {
	return s.encryptedSecretsMap
}

// GetSecretSource returns the workflowbuild.SecretSource for the secret store
func (s *secretStore) GetSecretSource() workflowbuild.SecretSource {
	return s.secretSource
}

func canUseOrgSecrets(data *types.WorkflowInvocationData, source workflowbuild.SecretSource) bool {
	if data.Owner.Type != ownerTypeOrganisation {
		return false
	}

	// Do not share org secrets when the repository is an advisory workspace
	if data.RepoIsAdvisoryWorkspace {
		return false
	}

	// Dependabot organization secrets can be used regardless of plan
	if source == workflowbuild.DependabotSecretSource {
		return true
	}

	if data.PlanOwner.PlanName == "free_organization" {
		// Only public repos on free org plans can use org secrets
		return !data.RepoIsPrivate
	}

	return true
}

type nilSecretStore struct{}

// GetDecryptedSecrets returns a map of secret names to decrypted secret values on a best effort basis
func (s *nilSecretStore) GetDecryptedSecrets(_ context.Context) map[string]string {
	return map[string]string{}
}

// GetEncryptedSecrets returns a map of secret names to encrypted secret value
func (s *nilSecretStore) GetEncryptedSecrets() map[string]build.EncryptedSecret {
	return map[string]build.EncryptedSecret{}
}

// GetSecretSource returns the workflowbuild.SecretSource for the secret store
func (s *nilSecretStore) GetSecretSource() workflowbuild.SecretSource {
	return workflowbuild.NoSecretSource
}
