package tester

import (
	"fmt"
	"strings"

	"github.com/github/authnd/internal/common/config"
	goconfig "github.com/github/go-config"
	"github.com/pkg/errors"
)

// Config defines the configuration to run the service.
type Config struct {
	config.CommonConfig

	HMACKeyList string `config:"octocat,env=AUTHND_HMAC_KEY"`
	// TestUserToken should be a PAT for the test user which has 'admin:public_key' scope
	TestUserToken string `config:"test,env=TEST_USER_GITHUB_TOKEN"`
	// AuthndTwirpURL url for the twirp server for the authnd API
	AuthndTwirpURL string

	GitHubAppPrivateKey string `config:",env=AUTHND_TESTER_GITHUB_APP_PRIVATE_KEY"`
}

// NewConfigFromEnvironment parses configuration from the environment and
// places it in a newly allocated Config struct.
func NewConfigFromEnvironment() (*Config, error) {
	cfg := &Config{}
	if err := goconfig.Load(cfg); err != nil {
		return nil, errors.WithStack(err)
	}
	cfg.ServiceName = "authnd_tester"

	if len(cfg.HMACKeyList) == 0 {
		return nil, errors.New("hmac key list is empty")
	}
	if len(cfg.TestUserToken) == 0 {
		return nil, errors.New("github token for test user is empty")
	}

	// translate 'production/canary' to 'production-canary' to be used in the authnd server url.
	// should be a noop for other environments.
	deploymentEnv := strings.ReplaceAll(cfg.DeploymentEnvironment, "/", "-")
	cfg.AuthndTwirpURL = fmt.Sprintf("https://authnd-%s.service.iad.github.net", deploymentEnv)

	return cfg, nil
}

// GetHMACKeys returns a slice of HMAC keys from the list provided in the HMACKeyList config value
func (cfg *Config) GetHMACKey() string {
	keys := strings.Split(cfg.HMACKeyList, ",")
	return keys[len(keys)-1]
}
