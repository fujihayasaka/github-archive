package config

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestConfigLoad(t *testing.T) {
	cfg := Config{}
	err := cfg.Load()
	assert.NoError(t, err)

	assert.NotEmpty(t, cfg.ServiceName)

	// validate nested properties are loaded
	assert.NotEmpty(t, cfg.Resources.AzureImageLocation)
	assert.NotEmpty(t, cfg.TwirpServer.HTTPPort)
	assert.NotEmpty(t, cfg.Worker.PoolSize)
}
