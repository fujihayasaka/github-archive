package aqueduct

import (
	"context"
	"testing"

	"github.com/github/sweagentd/internal/observability"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const (
	TestAppName       string = "test-app"
	TestAqueductURL   string = "aqueduct-lite:18081"
	TestAPIKey        string = "test-api-key"
	TestAPIKeyVersion int    = 123
)

func TestClientConfiguration(t *testing.T) {
	ctx := context.Background()
	ac, err := NewClient(
		ctx,
		observability.NewNoopExporters(),
		TestAppName,
		WithAqueductURL(TestAqueductURL),
		WithAPIKey(TestAPIKey),
		WithAPIKeyVersion(TestAPIKeyVersion),
	)
	require.NoError(t, err)
	require.NotEmpty(t, ac)
	assert.Equal(t, TestAppName, ac.AppName())
	assert.Equal(t, TestAqueductURL, ac.AqueductURL())

	assert.Equal(t, TestAPIKey, ac.getAPIKey())
	assert.Equal(t, TestAPIKeyVersion, ac.getAPIKeyVersion())
}
