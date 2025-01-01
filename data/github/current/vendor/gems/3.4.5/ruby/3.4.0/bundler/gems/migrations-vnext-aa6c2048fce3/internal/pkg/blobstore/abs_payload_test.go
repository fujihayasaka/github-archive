//go:build integrationtest

package blobstore

import (
	"context"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/integration"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_blobstore(t *testing.T) {
	absPayload := &Store{
		containerURL: integration.SetupAzuriteTest(t),
		logger:       log.NewNullLogger(),
	}

	key := "http://github.dev/acme/widgets/issues/6"
	err := absPayload.WritePayload(context.Background(), "foo", key, []byte("payload"))
	require.NoError(t, err)
	b, err := absPayload.GetPayload(context.Background(), "foo", key)
	require.NoError(t, err)
	assert.Equal(t, []byte("payload"), b)
}
