package config

import (
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v4"
	errs "github.com/pkg/errors"

	"github.com/github/launch/utils"
)

// See:
// - ADRs in Dreamlifter, especially https://github.com/github/dreamlifter/blob/master/docs/adrs/0306-service-to-service-credential-setup.md
// - 'GitHub Azure Tenants' LastPass folder
type AzureProviderConfig struct {
	// === Shared Secret ===
	// This secret is shared between launch and the TokenService and is used to sign
	// OAuth token requests to the token service
	TokenServiceKeyPEM  string `config:",env=TOKEN_SERVICE_KEY_PEM"`
	TokenServiceCertPEM string `config:",env=TOKEN_SERVICE_CERT_PEM"`

	// === GitHub AD APP ===
	// Our AD app is defined in our tenant and installed in the MS tenant
	// credentials
	// This lives in vault/LastPass, set in vault via:
	//     vault-secret -a launch -e production -k AZP_GH_APP_PRIVATE_KEY_PEM --value-from-file dev.key
	GHAppKeyPEM  string `config:",env=AZP_GH_APP_PRIVATE_KEY_PEM"`
	GHAppCertPEM string `config:",env=AZP_GH_APP_CERT_PEM"`
	GHAppID      string `config:",env=AZP_GH_APP_ID"`

	// === AAD ===
	// Url for AAD login
	AadOAuthBaseURL string `config:"https://login.microsoftonline.com,env=AAD_OAUTH2_BASE_URL"`

	// === Service Principal ===
	// tenant in which our SP cert vault lives
	// 33e01921-4d64-4f8c-a055-5bdaffd5e33d = AME
	VaultTenantID string `config:"33e01921-4d64-4f8c-a055-5bdaffd5e33d,env=AZP_VAULT_TENANT_ID"`
	// ID for our ServicePrinciple that lives in Azure DevOps Service Principal Tenant
	ServicePrincipalID string `config:",env=AZP_SP_ID"`

	// === Launch Actions S2S Service Principal ===
	// This is a service principal stored directly in Launch's vault
	// instead of in Azure Key Vault, replacing the above SPN.
	// https://github.com/github/actions-relaunch/issues/667
	ActionsServiceS2SSPNClientSecret string `config:",env=ACTIONS_SERVICE_SPN_CLIENT_SECRET"`
	ActionsServiceS2SSPNClientID     string `config:",env=ACTIONS_SERVICE_SPN_CLIENT_ID"`
	ActionsServiceS2SSPNTenantID     string `config:",env=ACTIONS_SERVICE_SPN_TENANT_ID"`

	// === AZP APIs ===
	// APIs for repo-level APIs (not S2S calls to create orgs)
	RepoAPIsBaseURL string `config:"https://pipelines.actions.githubusercontent.com,env=REPO_APIS_BASE_URL"`
	// ExternalRepoAPIsBaseURL is the external facing URL that is needed in GHES to allow access from outside the GHES instance.
	ExternalRepoAPIsBaseURL string `config:",env=EXTERNAL_REPO_APIS_BASE_URL"`
	// resource for creating tokens that give access to AZP APIs - this the AD ID of "Visual Studio Team Services", AKA Azure DevOps. Stable across envs
	AZPResource string `config:"0000005A-0000-8888-8000-000000000000,env=AZP_TOKEN_RESOURCE"`
	// AZP's tenant - this is stable across environments
	AZPTenantID string `config:"VSOGHAAD.onmicrosoft.com,env=AZP_AZP_TENANT_ID"`
	// region we create our AZP orgs in
	OrgRegion string `config:"EUS2,env=AZP_ORG_REGION"`
	// the org create call currently has a different API base URL
	OrgCreateBaseURL string `config:",env=AZP_ORG_CREATE_API_BASE_URL"`
	// Base URLs for Pipeline scale units
	PipelineBaseUrls string `config:"https://pipelines.actions.githubusercontent.com,env=PIPELINE_SCALE_UNIT_URLS"`
	// Token service endpoint
	TokenServiceBaseURL string `config:"https://tokenghub.actions.githubusercontent.com,env=TOKEN_SERVICE_BASE_URL"`
	// Runner endpoint
	RunnerServiceBaseURL string `config:"https://runner.actions.githubusercontent.com,env=RUNNER_SERVICE_BASE_URL"`
	// ArtifactCache endpoint
	ACServiceBaseURL string `config:"https://artifactcache.actions.githubusercontent.com,env=AC_SERVICE_BASE_URL"`

	// Force Token over AAD calls, used in local devfabric configurations until AAD is removed
	ForceTokenOverAAD bool `config:"false,env=AZP_FORCE_TOKEN_OVER_AAD"`

	// controls how long we wait on another process to finish creating an azure org before we also attempt creation, and how frequently we check for locks
	ResourcesLockPollFreq time.Duration `config:"1s,env=AZP_RESOURCES_LOCK_POLL_FREQ"`
	ResourcesLockTimeout  time.Duration `config:"1m,env=AZP_RESOURCES_LOCK_TIMEOUT"`

	// === Fields not loaded by github/go/config, but set on Parse() ==
	GHAppPrivateKey *rsa.PrivateKey
	GHAppCert       *x509.Certificate

	TokenServicePrivateKey *rsa.PrivateKey
	TokenServiceCert       *x509.Certificate

	// === HMAC Auth ===
	AuthVaultName      string `config:",env=AZP_AUTH_VAULT_NAME"`
	RealmWideVaultName string `config:",env=AZP_REALM_WIDE_VAULT_NAME"`
}

func (c *AzureProviderConfig) Parse() error {
	var err error

	// GitHub App private key and cert
	c.GHAppPrivateKey, err = c.parsePrivateKey(c.GHAppKeyPEM)
	if err != nil {
		return errs.Wrap(err, "failed to parse azp app private key")
	}

	c.GHAppCert, err = c.parseCert(c.GHAppCertPEM)
	if err != nil {
		return errs.Wrap(err, "failed to parse azp app cert")
	}

	// Shared secret for token service
	if c.TokenServiceKeyPEM != "" {
		c.TokenServicePrivateKey, err = c.parsePrivateKey(c.TokenServiceKeyPEM)
		if err != nil {
			return errs.Wrap(err, "failed to parse token service private key")
		}
	}

	if c.TokenServiceCertPEM != "" {
		c.TokenServiceCert, err = c.parseCert(c.TokenServiceCertPEM)
		if err != nil {
			return errs.Wrap(err, "failed to parse token service cert")
		}
	}

	return nil
}

func (c *AzureProviderConfig) parsePrivateKey(PEM string) (*rsa.PrivateKey, error) {
	key := utils.UnescapeConsulKVString(PEM)
	privateKey, err := jwt.ParseRSAPrivateKeyFromPEM([]byte(key))
	if err != nil {
		return nil, errs.Wrap(err, "failed to parse private key from PEM")
	}

	return privateKey, nil
}

func (c *AzureProviderConfig) parseCert(PEM string) (*x509.Certificate, error) {
	certPEM := utils.UnescapeConsulKVString(PEM)
	block, _ := pem.Decode([]byte(certPEM))
	if block == nil {
		return nil, errs.New("missing PEM data")
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil, err
	}

	return cert, nil
}

func (c *AzureProviderConfig) PipelineBaseUrlsList() []string {
	return strings.Split(strings.TrimSpace(c.PipelineBaseUrls), "\n")
}
