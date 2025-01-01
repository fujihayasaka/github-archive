package azp

import (
	"context"
	"crypto/rsa"
	"time"

	"github.com/github/launch/types"
	"github.com/github/launch/workflowbuild/azp/azptypes"
)

// S2SClient gives us access to AZP's APIs as the GitHub Actions AD App
type S2SClient interface {
	// CreateTenantWithResources sets up the AZP resources required for a GH Repo to be buildable or User/Organization to have builds
	CreateTenantWithResources(ctx context.Context, globalID, ownerGlobalID types.GlobalID, name types.RepositoryFullName, key *rsa.PublicKey, planName string, billingOwnerCreatedAt time.Time) (*azptypes.CreationResult, error)
}

// KeyVaultClient allows getting secrets from Azure KeyVault
type KeyVaultClient interface {
	// GetSecrets gets a secret from Azure KeyVault
	GetSecret(ctx context.Context, vaultName, secretName string) (*KeyVaultSecret, error)
}

type KeyVaultSecret struct {
	Value      string `json:"value"`
	Attributes struct {
		ValidFrom  int64 `json:"nbf"`
		ValidUntil int64 `json:"exp"`
	} `json:"attributes"`
}
