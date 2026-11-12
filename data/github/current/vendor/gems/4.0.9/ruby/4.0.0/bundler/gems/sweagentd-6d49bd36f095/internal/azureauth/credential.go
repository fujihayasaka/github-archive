// Package azureauth provides Azure credential helpers using OIDC workload identity.
package azureauth

import (
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/github/sweagentd/internal/goerrors"
)

// NewAzureCredential builds an OIDC WorkloadIdentityCredential.
func NewAzureCredential(tenantID, clientID string) (azcore.TokenCredential, error) {
	var missing []string
	if tenantID == "" {
		missing = append(missing, "tenantID")
	}
	if clientID == "" {
		missing = append(missing, "clientID")
	}
	if len(missing) > 0 {
		return nil, goerrors.Errorf("missing required Azure credential fields: %s", strings.Join(missing, ", "))
	}

	oidcCred, err := azidentity.NewWorkloadIdentityCredential(&azidentity.WorkloadIdentityCredentialOptions{
		ClientID: clientID,
		TenantID: tenantID,
	})
	if err != nil {
		return nil, goerrors.Errorf("failed to create WorkloadIdentityCredential: %w", err)
	}

	return oidcCred, nil
}
