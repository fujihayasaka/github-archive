package azureblob

import (
	"context"
	"io"
	"net/http"
	"testing"
	"time"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/testing/data"
	"github.com/golang/snappy"

	"github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func newLocalBlobClient(t *testing.T) *LiveClient {
	client, err := NewLocalClient("attestations")
	require.NoError(t, err)

	err = client.CreateContainer(context.Background(), "attestations")
	require.NoError(t, err)

	return client
}

func TestDownloadAttestation(t *testing.T) {
	ctx := context.Background()
	client := newLocalBlobClient(t)

	expectedBundle := data.SigstoreBundle(t)
	expectedBundleSG, err := bundle.NewBundle(expectedBundle)
	require.NoError(t, err)

	repoID := uint64(456)
	r := attestation.Record{
		RepositoryID: &repoID,
		CreatedAt:    time.Now(),
		ID:           123,
	}

	err = client.StoreAttestation(ctx, r, expectedBundleSG)
	assert.NoError(t, err)

	actualBundle, err := client.DownloadAttestation(ctx, r)
	assert.NoError(t, err)
	assert.Equal(t, actualBundle, expectedBundle)
}

func TestStoreAttestation_BlobOverwritten(t *testing.T) {
	ctx := context.Background()
	client := newLocalBlobClient(t)

	b, err := bundle.NewBundle(data.SigstoreBundle(t))
	require.NoError(t, err)

	r := attestation.Record{
		RepositoryID: new(uint64),
		CreatedAt:    time.Now(),
		ID:           456,
	}

	err = client.StoreAttestation(ctx, r, b)
	assert.NoError(t, err)

	sb, err := bundle.NewBundle(data.SigstoreBundleSLSA1Provenance(t))
	require.NoError(t, err)
	err = client.StoreAttestation(ctx, r, sb)
	assert.NoError(t, err)
}

func TestGenerateSASWithBlobClient(t *testing.T) {
	ctx := context.Background()
	client := newLocalBlobClient(t)

	expectedBundle, err := bundle.NewBundle(data.SigstoreBundle(t))
	require.NoError(t, err)

	r := attestation.Record{
		RepositoryID: new(uint64),
		CreatedAt:    time.Now(),
		ID:           123,
	}

	err = client.StoreAttestation(ctx, r, expectedBundle)
	assert.NoError(t, err)

	sas, err := client.GenerateSASUrl(ctx, r)
	assert.NoError(t, err)

	resp, err := http.Get(sas) //#nosec
	assert.NoError(t, err)
	defer resp.Body.Close()

	assert.Equal(t, 200, resp.StatusCode)
	assert.Equal(t, "application/x-snappy", resp.Header.Get("Content-Type"))
	b, err := io.ReadAll(resp.Body)
	assert.NoError(t, err)

	decompressed, err := snappy.Decode(nil, b)
	assert.NoError(t, err)
	assert.NotNil(t, decompressed)

	var pb bundle.Bundle
	err = pb.UnmarshalJSON(decompressed)
	assert.NoError(t, err)
}
