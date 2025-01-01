package aqueduct

import (
	"fmt"

	"github.com/github/go-config"
)

type Config struct {
	Addr              string `config:"http://localhost:28141,env=AQUEDUCT_URL"`
	AppName           string `config:"hosted-compute-ims,env=AQUEDUCT_APP"`
	APIKey            string `config:",env=AQUEDUCT_API_KEY"`
	APIKeyVersion     int    `config:"0,env=AQUEDUCT_API_KEY_VERSION"`
	EncryptionKeyList string `config:"abcdef123456/[^=,env=ENCRYPTION_KEY_LIST"`
}

func (c *Config) Load() error {
	if err := config.Load(c); err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	return nil
}
