package main

import (
	"github.com/github/launch/clients/launchredis"
	"github.com/github/launch/pkg/abreaker"
	"github.com/github/launch/pkg/launchconfig"
	"github.com/github/launch/utils/roundtrippers"
)

// Config is the complete configuration definition for the launch-chatops
// application.
//
// It is read from the environment variables present in the container on which
// this application is run, and initialized using the 'config' package
// (see: github.com/github/go-config/v2)
type Config struct {
	launchconfig.CommonConfig

	DeployerTwirpAddr string `config:",env=DEPLOYER_TWIRP_ADDR,required"`

	// The secret to use to sign requests to deployer for HMAC verification.
	// This should match one of the secrets in Deployer's DEPLOYER_HMAC_VERIFY_SECRETS
	DeployerHMACSigningSecret string `config:",env=DEPLOYER_HMAC_SECRET,required"`

	// GitHub Twirp Configuration
	GitHubTwirpHMACSecret string `config:",env=GITHUB_TWIRP_HMAC_SECRET,required"`
	GitHubTwirpAddr       string `config:",env=GITHUB_TWIRP_ADDR,required"`

	SecretsAppRelayID string `config:",env=GITHUB_SECRETS_APP_RELAY_ID,required"`

	BreakerConfig abreaker.Config
	roundtrippers.RoundTripperConfig

	launchredis.RedisConfig

	// This sets up RBAC and 2FA capabilities for high risk chatops.
	SecurityConfigFile string `config:"/etc/launch-chatops/security/security-config.yaml,env=SECURITY_CONFIG_FILE"`
	LDAPConfigFile     string `config:"/etc/launch-chatops/security/ldap-config.yaml,env=LDAP_CONFIG_FILE"`
	LDAPPassword       string `config:",env=LDAP_BINDPW"`
	FidoURL            string `config:"https://fido-challenger.githubapp.com,env=FIDO_URL"`
	ChatterboxURL      string `config:"https://chatterbox.githubapp.com,env=CHATTERBOX_URL"`
	ChatterboxToken    string `config:",env=CHATTERBOX_TOKEN"`
}
