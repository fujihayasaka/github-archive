package service

import (
	"context"
	"database/sql"
	"testing"

	exceptions "github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/mock"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/stretchr/testify/require"
)

// TODO: Use an actual release attestation from attester and update this test data
const TestReleasesSAN = "https://github.com/bdehamer/attest-demo/.github/workflows/checksums.yml@refs/heads/main"
const TestReleasesTag = "v2.67.0"

func NewTestTMA(t *testing.T) *TMA {
	return NewTestTMAWithStore(t, storage.NewInMemoryStore())
}

func NewTestTMAWithStore(t *testing.T, store storage.Store) *TMA {
	tma, err := NewTMA(store, "TestGitCommitSHA", attestation.LocalDataVerifier(t), newNullReporter(), TestReleasesSAN)
	require.NoError(t, err)
	return tma
}

type cleanUp = func(t *testing.T)

func NewTMAWithLocalDockerStorage(t *testing.T) (*TMA, cleanUp) {
	var db storage.DatabaseEndpoints
	var tx *sql.Tx

	db.Primary, tx = mysql.NewTransactionalDatabase(t)
	db.Replica = db.Primary

	azBlobClient, err := azureblob.NewLocalClient("attestations")
	require.NoError(t, err)

	err = azBlobClient.CreateContainer(context.Background(), "attestations")
	require.NoError(t, err)

	store := storage.NewLiveStore(azBlobClient, &db, nil)

	cleanUp := func(t *testing.T) {
		err = azBlobClient.DeleteContainer(context.Background(), "attestations")
		require.NoError(t, err)

		// nolint:errcheck
		tx.Rollback()
	}

	return NewTestTMAWithStore(t, store), cleanUp
}

// newNullReporter returns a mock sentry reporter
func newNullReporter() *exceptions.Reporter {
	fn := func(context.Context, []byte) error {
		return nil
	}
	exporter := mock.NewExporter(fn)

	reporter, _ := exceptions.NewReporter(
		exceptions.WithExporter(exporter),
		exceptions.WithApplication("tma-test-suite"),
		exceptions.WithHostname("localhost"),
	)

	return reporter
}
