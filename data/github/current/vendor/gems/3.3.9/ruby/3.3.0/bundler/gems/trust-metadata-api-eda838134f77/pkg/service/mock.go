package service

import (
	"context"
	"testing"

	exceptions "github.com/github/go-exceptions"
	"github.com/github/go-exceptions/exporters/mock"
	"github.com/github/trust-metadata-api/pkg/storage"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	tmatesting "github.com/github/trust-metadata-api/testing"
	"github.com/stretchr/testify/require"
)

func NewTestTMA(t *testing.T) *TMA {
	return NewTestTMAWithStore(t, storage.NewInMemoryStore())
}

func NewTestTMAWithStore(t *testing.T, store storage.Store) *TMA {
	tma, err := NewTMA(store, "TestGitCommitSHA", tmatesting.TMAVerifier(t), newNullReporter())
	require.NoError(t, err)
	return tma
}

func NewTestTMAWithDB(t *testing.T, db *storage.DatabaseEndpoints) *TMA {
	store := storage.NewLiveStore(azureblob.NewInMemoryClient(), db)
	tma, err := NewTMA(store, "TestGitCommitSHA", tmatesting.TMAVerifier(t), newNullReporter())
	require.NoError(t, err)
	return tma
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
