package store

import (
	"context"
	"testing"

	"github.com/github/turboscan/ts/config"
	"github.com/stretchr/testify/require"
)

func TestUploadDownloadAzure(t *testing.T) {
	cfg, err := config.Load()
	require.NoError(t, err)

	ctx := context.Background()
	ss := NewSarifStore(config.STORAGE_AZURE, cfg)

	err = ss.Open(ctx)
	require.NoError(t, err)
	defer ss.Close(ctx)

	data := []byte("abc")
	path := "testing/somebytes"
	requireUpload(t, ctx, ss, data, path)

	buf, err := ss.Download(ctx, path)
	require.NoError(t, err)
	require.Equal(t, data, buf.Bytes())
}
