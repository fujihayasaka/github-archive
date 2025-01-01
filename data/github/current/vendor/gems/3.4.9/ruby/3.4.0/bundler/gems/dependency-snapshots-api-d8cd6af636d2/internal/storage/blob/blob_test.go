package blob_test

import (
	"context"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/storage/blob/testutility"
	"github.com/stretchr/testify/require"
)

func TestBasicBlobFunctionality(t *testing.T) {
	client := testutility.GetTestBlobStorage(t)
	ctx := context.Background()

	url, err := client.CreateBlob(ctx, "some/blob/name", []byte{1, 2, 3, 4, 5, 6})
	require.NoError(t, err)
	require.NotEqual(t, "", url)

	contents, err := client.GetBlob(ctx, url)
	require.NoError(t, err)
	require.Equal(t, []byte{1, 2, 3, 4, 5, 6}, contents)
}
