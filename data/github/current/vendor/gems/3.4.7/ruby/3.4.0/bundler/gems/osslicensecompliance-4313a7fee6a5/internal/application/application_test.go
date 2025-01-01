package application_test

import (
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/osslicensecompliance/internal/application"
	"github.com/github/osslicensecompliance/internal/config"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func TestNewApplication_InMemoryStorage(t *testing.T) {
	cfg := &config.Config{Mode: "test", AzureBlobEndpoint: "http://127.0.0.1:10100/devstoreaccount1"}
	app, err := application.New(cfg, log.Named("test"), stats.NullStatter)
	require.NoError(t, err)

	assert.NotNil(t, app.Subsystems.Storage)
}
