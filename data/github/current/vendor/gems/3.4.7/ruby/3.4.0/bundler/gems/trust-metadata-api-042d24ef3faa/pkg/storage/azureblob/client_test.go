package azureblob

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/sas"
	"github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/testing/data"
)

func TestBuildBlobName(t *testing.T) {
	repoID := uint64(4567)
	testcases := []struct {
		createdAt    time.Time
		expectErr    bool
		expectedErr  error
		expectedPath string
		name         string
		purl         string
		repositoryID *uint64
	}{
		{
			// 2021-03-18 23:00:00 UTC
			createdAt:    time.Date(2021, time.March, 18, 23, 0, 0, 0, time.UTC),
			expectedPath: "4567/2021/03/18/123.json.sn",
			name:         "Dotcom attestation",
			repositoryID: &repoID,
		},
		{
			// 2021-03-18 23:00:00 UTC-8
			createdAt:    time.Date(2021, time.March, 18, 23, 0, 0, 0, time.FixedZone("PST", -8*60*60)),
			expectedPath: "4567/2021/03/19/123.json.sn",
			name:         "Dotcom attestation with UTC-8 createdAt time",
			repositoryID: &repoID,
		},
		{
			createdAt:    time.Date(2021, time.March, 18, 23, 0, 0, 0, time.UTC),
			expectedPath: "0/2021/03/18/123.json.sn",
			name:         "npm attestation",
			purl:         "pkg:npm/foo/bar@12.3.1",
		},
		{
			createdAt:    time.Date(2021, time.March, 18, 23, 0, 0, 0, time.UTC),
			expectErr:    true,
			expectedErr:  errInvalidRecord,
			expectedPath: "0/2021/03/18/123.json.sn",
			name:         "invalid record",
		},
	}

	for _, tc := range testcases {
		r := &attestation.Record{
			CreatedAt:    tc.createdAt,
			ID:           123,
			Purl:         tc.purl,
			RepositoryID: tc.repositoryID,
		}

		actualPath, err := BuildBlobNameByDomain(*r)
		if tc.expectErr {
			assert.Zero(t, actualPath, "test '%s': expected path to be empty, but got '%s'", tc.name, actualPath)
			assert.Error(t, err, "test '%s': expected error, but got none", tc.name)
			assert.ErrorAs(t, err, &tc.expectedErr, "test '%s': expected error of type '%T', but got '%T'", tc.name, tc.expectedErr, err)
		} else {
			assert.Equal(t, tc.expectedPath, actualPath, "test '%s': constructed path does not match expected path", tc.name)
			assert.NoError(t, err, "test '%s': expected no error, but got '%v'", tc.name, err)
		}
	}
}

func TestStoreAttestation(t *testing.T) {
	testcases := []struct {
		azClient        azureClient
		uploadSizeLimit int
		expectErr       bool
		expectedErrType error
	}{
		{
			azClient:        &MockAzureClient{},
			uploadSizeLimit: uploadLimitInBytes,
			expectErr:       false,
		},
		{
			azClient:        &UploadFailureClient{},
			uploadSizeLimit: uploadLimitInBytes,
			expectErr:       true,
		},
		{
			azClient:        &MockAzureClient{},
			uploadSizeLimit: 1,
			expectErr:       true,
			expectedErrType: errUploadLimitExceeded,
		},
	}

	for _, tc := range testcases {
		b, err := bundle.NewBundle(data.SigstoreBundle(t))
		require.NoError(t, err)

		r := attestation.Record{
			RepositoryID: new(uint64),
			CreatedAt:    time.Now(),
			ID:           123,
		}

		client := LiveClient{
			azClient:  tc.azClient,
			container: "attestations",
			observability: observabilityConfig{
				logger:  log.NewNullLogger(),
				metrics: stats.NullStatter,
			},
			uploadLimit: tc.uploadSizeLimit,
		}
		err = client.StoreAttestation(context.Background(), r, b)
		if tc.expectErr {
			assert.Error(t, err)
			if tc.expectedErrType != nil {
				assert.ErrorIs(t, tc.expectedErrType, err)
			}
		} else {
			assert.NoError(t, err)
		}
	}
}

func TestGenerateSAS(t *testing.T) {
	testcases := []struct {
		azClient      azureClient
		expectErr     bool
		signSASParams func(sas.BlobSignatureValues) (sas.QueryParameters, error)
	}{
		{
			azClient:      &MockAzureClient{},
			expectErr:     false,
			signSASParams: signSASParamsWithSharedKey,
		},
		{
			azClient:  &GenerateSASFailureClient{},
			expectErr: true,
			signSASParams: func(sas.BlobSignatureValues) (sas.QueryParameters, error) {
				return sas.QueryParameters{}, fmt.Errorf("failed to generate SAS")
			},
		},
	}

	for _, tc := range testcases {
		ctx := context.Background()
		b, err := bundle.NewBundle(data.SigstoreBundle(t))
		require.NoError(t, err)

		r := attestation.Record{
			RepositoryID: new(uint64),
			CreatedAt:    time.Now(),
			ID:           123,
		}

		client, err := NewLocalClient("attestations")
		require.NoError(t, err)

		client.azClient = tc.azClient
		client.signSASParams = tc.signSASParams

		err = client.StoreAttestation(ctx, r, b)
		assert.NoError(t, err)

		generatedSAS, err := client.GenerateSASUrl(ctx, r)
		if tc.expectErr {
			assert.Error(t, err)
			assert.Zero(t, generatedSAS)
		} else {
			assert.NoError(t, err)
		}
	}
}
