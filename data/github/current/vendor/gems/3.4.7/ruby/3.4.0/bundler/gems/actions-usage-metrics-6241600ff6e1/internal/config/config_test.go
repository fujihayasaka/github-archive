package config

import (
	"os"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestLoadKustoConfig(t *testing.T) {
	os.Clearenv()
	os.Setenv("KUSTO_CONNECTION_STRING", "test-connection-string")
	os.Setenv("KUSTO_DATABASE", "test-db")

	config, err := Load[KustoConfig]()
	assert.NoError(t, err)
	assert.Equal(t, "test-connection-string", config.ConnectionString)
	assert.Equal(t, "test-db", config.Database)
}

func TestLoadKustoConfigDefaults(t *testing.T) {
	os.Clearenv()

	config, err := Load[KustoConfig]()
	assert.NoError(t, err)
	assert.Equal(t, "", config.ConnectionString)
	assert.Equal(t, "", config.Database)
}
