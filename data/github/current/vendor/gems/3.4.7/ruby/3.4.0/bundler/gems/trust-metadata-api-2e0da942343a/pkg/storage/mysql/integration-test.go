package mysql

import (
	"context"
	"crypto/x509"
	"database/sql"
	"testing"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/trust-metadata-api/test/data"
	"github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/require"
)

const TestDBURI = "tma:TMAdevP4ssw0rd!@tcp(127.0.0.1:3337)/tma_dev?parseTime=true"

func transactionDBSetup(t *testing.T) (*sql.DB, *sql.Tx) {
	db, err := sql.Open("mysql", TestDBURI)
	require.NoError(t, err)
	// Reset database every time we run tests
	_, err = db.Exec("TRUNCATE TABLE attestations")
	require.NoError(t, err)
	_, err = db.Exec("TRUNCATE TABLE attestations_subjects")
	require.NoError(t, err)
	tx, err := db.BeginTx(context.Background(), nil)
	require.NoError(t, err)
	return db, tx
}

// NewTransactionalDatabase creates a LiveDatabase with a cancellable transaction.
// Note that you must explicitly call cancel() to rollback the transaction.
// This should be used for any integration tests higher than the mysql package layer
func NewTransactionalDatabase(t *testing.T) (*LiveDatabase, *sql.Tx) {
	db, tx := transactionDBSetup(t)
	return NewLiveDatabaseFromConn(db, log.NewNullLogger(), stats.NullStatter), tx
}

// newTxDatabase creates a LiveDatabase using a *sql.Tx instance when
// creating the connection. This should be used for mysql integration tests
// that database methods directly. The exported NewTransactionalDatabase function
// is for integration tests in other layers.
// nolint:unused // While this function is used, the linter keeps failing by claiming it is unused
func newTxDatabase(t *testing.T) (*LiveDatabase, *sql.Tx) {
	_, tx := transactionDBSetup(t)
	return NewLiveDatabaseFromConn(tx, log.NewNullLogger(), stats.NullStatter), tx
}

func CreateTestCert(t *testing.T) *x509.Certificate {
	pbundle := data.SigstoreBundleAttestDemoSBOM(t)
	bundle, err := bundle.NewBundle(pbundle)
	require.NoError(t, err)

	leaf := bundle.VerificationMaterial.GetCertificate()
	cert, err := x509.ParseCertificate(leaf.RawBytes)
	require.NoError(t, err)
	return cert
}
