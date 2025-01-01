package cocofix

import (
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/config"
	"github.com/pkg/errors"
)

type CapiIntegration struct {
	ID  string
	Key string
}

type CapiConfig struct {
	capiModelName CapiModelName

	ghAppToken string

	integrations map[ts.CapiIntegrationType]CapiIntegration
}

func NewCapiConfig(cfg *config.Config) *CapiConfig {
	model := cfg.CapiModelName
	var modelName CapiModelName
	if model != "" {
		modelName = CapiModelName(model)
	} else {
		modelName = CapiModelNameDefault
	}

	i := map[ts.CapiIntegrationType]CapiIntegration{
		ts.CapiIntegrationCodeScanning: {ID: cfg.CapiGhasIntegrationID, Key: cfg.CapiGhasHMACKey},
		ts.CapiIntegrationDependabot:   {ID: cfg.CapiGhasIntegrationID, Key: cfg.CapiGhasHMACKey},
		ts.CapiIntegrationCCR:          {ID: cfg.CapiGitHubIntegrationID, Key: cfg.CapiGitHubHMACKey},
	}

	return &CapiConfig{
		ghAppToken:    cfg.GitHubAppToken,
		capiModelName: modelName,
		integrations:  i,
	}
}

func TestCapiConfig(cfg *config.Config, realCreds bool) *CapiConfig {
	dIntegration := CapiIntegration{
		ID:  cfg.CapiGhasIntegrationID,
		Key: "fake",
	}
	c := &CapiConfig{
		capiModelName: CapiModelNameDefault,
		ghAppToken:    "fake",
	}

	if realCreds {
		c.ghAppToken = cfg.GitHubAppToken
		dIntegration.Key = cfg.CapiGhasHMACKey
	}

	c.integrations = map[ts.CapiIntegrationType]CapiIntegration{
		ts.CapiIntegrationCodeScanning: dIntegration,
		ts.CapiIntegrationDependabot:   dIntegration,
		ts.CapiIntegrationCCR:          dIntegration,
	}

	return c
}

func (c *CapiConfig) GetIntegrationEnv(it ts.CapiIntegrationType) (*CapiIntegration, error) {
	i, ok := c.integrations[it]
	if !ok {
		return nil, errors.Errorf("integration %d not found", it)
	}

	return &i, nil
}
