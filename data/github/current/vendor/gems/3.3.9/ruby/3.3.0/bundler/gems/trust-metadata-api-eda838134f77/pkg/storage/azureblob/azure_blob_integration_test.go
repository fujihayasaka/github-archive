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

func TestDownloadAttestation(t *testing.T) {
	ctx := context.Background()
	client, err := NewLocalClient("attestations")
	require.NoError(t, err)

	err = client.CreateContainer(ctx, "attestations")
	require.NoError(t, err)

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

func TestStoreAttestation_BlobAlreadyExists(t *testing.T) {
	ctx := context.Background()
	client, err := NewLocalClient("attestations")
	require.NoError(t, err)

	err = client.CreateContainer(ctx, "attestations")
	require.NoError(t, err)

	b, err := bundle.NewBundle(data.SigstoreBundle(t))
	require.NoError(t, err)

	r := attestation.Record{
		RepositoryID: new(uint64),
		CreatedAt:    time.Now(),
		ID:           456,
	}

	err = client.StoreAttestation(ctx, r, b)
	assert.NoError(t, err)

	err = client.StoreAttestation(ctx, r, b)
	assert.NoError(t, err)
}

/*
NOTE: the Azurite container used in integration tests does not validate the
client's IP range against the IP range specified in the
sas.BlobSignatureValues.IPRange field, so a client IP range is not configured
in this integration test.
See https://github.com/Azure/Azurite/blob/76f626284e4b4b58b95065bb3c92351f30af7f3d/src/blob/authentication/BlobSASAuthenticator.ts#L554
*/
func TestGenerateSASWithBlobClient(t *testing.T) {
	// We need to provide an IP address so the SAS generation function does not fail.
	ctx := context.WithValue(context.Background(), ClientIPAddrCtxKeyName, "127.0.0.1")
	client, err := NewLocalClient("attestations")
	require.NoError(t, err)

	err = client.CreateContainer(ctx, "attestations")
	require.NoError(t, err)

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
