package aqueduct

import (
	"testing"

	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/github-telemetry-go/log"
	stats "github.com/github/go-stats"
	"github.com/stretchr/testify/require"
)

func TestNewClientRequiresConfiguredAqueduct(t *testing.T) {
	cfg := &config.Config{}
	require.NoError(t, cfg.InitDefaultLogger())
	logger := log.Named("test")

	_, err := NewClient(cfg, logger, stats.NullStatter)
	require.ErrorIs(t, err, ErrNotConfigured)
}

func TestNewClientRejectsEnterprise(t *testing.T) {
	cfg := &config.Config{
		Enterprise:      true,
		AqueductEnabled: true,
		AqueductURL:     "http://localhost:1234",
		AqueductAppName: "test",
		AqueductAPIKey:  "secret",
	}
	require.NoError(t, cfg.InitDefaultLogger())
	logger := log.Named("test")

	_, err := NewClient(cfg, logger, stats.NullStatter)
	require.ErrorIs(t, err, ErrNotSupportedOnGHES)
}
