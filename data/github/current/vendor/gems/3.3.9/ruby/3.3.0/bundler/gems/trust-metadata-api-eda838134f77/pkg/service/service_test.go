package service

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/github/trust-metadata-api/pkg/storage"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/testing/data"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/mock"

	"github.com/github/trust-metadata-api/pkg/attestation"
)

const (
	TestPurl = "pkg:npm/foo/bar@12.3.1"
	//nolint:gosec
	SubjectDigest = "sha256:00522a5ecf4f877384d6781bea67a9b3827209cb6787e6ddceb8fd792a5f416c"
	SubjectName   = "foo/bar"
)

type MockDB struct {
	mysql.InMemoryDatabase
	mock.Mock
}

func newMockDatabaseEndpoints() *storage.DatabaseEndpoints {
	var mock MockDB

	return &storage.DatabaseEndpoints{
		Primary: &mock,
		Replica: &mock,
	}
}

func (m *MockDB) GetAttestationsByPurl(_ context.Context, _ attestation.IdentifiersNPM) ([]attestation.Record, error) {
	m.Called()
	return []attestation.Record{
		{SubjectDigest: "sha512:bbfd372fc9beeb777fe35d05bb10c0c70a9733d366a75fed7dd18866c7391de3ee7e88ba74dd47abf3e15c845e547fcf0e5c3da80854c751554224d3a6d4e55f"},
	}, nil
}

func (m *MockDB) GetAttestationByPurlPredicateType(_ context.Context, _ attestation.IdentifiersNPM, _ []string) (*attestation.Record, error) {
	m.Called()
	return &attestation.Record{}, nil
}

// clientFacingError is a helper function to return the client facing error, if
// one exists, from the provided error.
func clientFacingError(err error) string {
	var cfe ClientFacingError
	if errors.As(err, &cfe) {
		return cfe.ClientFacingError()
	}
	return "internal error"
}

func TestService_NewTMA(t *testing.T) {
	tma := NewTestTMA(t)
	assert.Equal(t, "TestGitCommitSHA", tma.GitCommit)
}

func verifyBundle(t *testing.T, b *protobundle.Bundle) error {
	tma := NewTestTMA(t)
	bundle, err := sgbundle.NewBundle(b)
	if err != nil {
		return fmt.Errorf("error validating bundle: %w", err)
	}
	ctx := context.Background()
	_, err = tma.VerifyBundle(ctx, bundle)
	return err
}

func verifyBundleSuccess(t *testing.T, b *protobundle.Bundle) {
	err := verifyBundle(t, b)
	assert.NoError(t, err)
}

func TestVerifyBundle(t *testing.T) {
	verifyBundleSuccess(t, data.SigstoreBundle(t))
}

func TestVerifyBundleWithPublicKey(t *testing.T) {
	verifyBundleSuccess(t, data.SigstoreBundlePublicKey(t))
}

func TestVerifyBundleWithV02Bundle(t *testing.T) {
	verifyBundleSuccess(t, data.SigstoreJs220ProtoBundle(t))
}

func TestVerifyBundleWithV03Bundle(t *testing.T) {
	verifyBundleSuccess(t, data.SigstoreJs300ProtoBundle(t))
}

func TestVerifyBundleInvalidSignature(t *testing.T) {
	bundle := data.SigstoreBundleInvalidSignature(t)
	err := verifyBundle(t, bundle)
	assert.Error(t, err)
}

func TestVerifyBundleInvalidNoLogID(t *testing.T) {
	bundle := data.SigstoreBundleInvalidNoLogID(t)
	err := verifyBundle(t, bundle)
	assert.Error(t, err)
}

func TestVerifyBundleInvalidNoSignature(t *testing.T) {
	bundle := data.SigstoreBundleInvalidNoSignature(t)
	err := verifyBundle(t, bundle)
	assert.Error(t, err)
}

func TestVerifyBundleInvalidSET(t *testing.T) {
	bundle := data.SigstoreBundleInvalidSET(t)
	err := verifyBundle(t, bundle)
	assert.Error(t, err)
}

func TestVerifyBundleInvalidMismatchedSignatures(t *testing.T) {
	bundle := data.SigstoreBundleInvalidMismatchedSignatures(t)
	err := verifyBundle(t, bundle)
	assert.Error(t, err)
}

func Test_shouldReport(t *testing.T) {
	type args struct {
		err error
	}
	tests := []struct {
		name string
		args args
		want string
	}{
		{
			name: "mysql.ErrMySQLConn",
			args: args{NewInternalError(&mysql.ErrMySQLConn{})},
			want: "mysql_connection",
		},
		{
			name: "mysql.ErrMySQLClose",
			args: args{NewInternalError(&mysql.ErrMySQLClose{})},
			want: "mysql_connection",
		},
		{
			name: "mysql.ErrConvertFromSQLC",
			args: args{NewInternalError(&mysql.ErrConvertFromSQLC{})},
			want: "sqlc_conversion",
		},
		{
			name: "mysql.ErrConvertToSQLC",
			args: args{NewInternalError(&mysql.ErrConvertToSQLC{})},
			want: "sqlc_conversion",
		},
		{
			name: "azureblob.ErrBlobDownloadFailed",
			args: args{NewInternalError(&azureblob.ErrBlobDownloadFailed{})},
			want: "blob_storage_download",
		},
		{
			name: "InternalError",
			args: args{NewInternalError(fmt.Errorf("some other error"))},
			want: "internal",
		},
		{
			name: "random error",
			args: args{fmt.Errorf("some other error")},
			want: "",
		},
		{
			name: "BadRequestError",
			args: args{NewBadRequestError(fmt.Errorf("some other error"))},
			want: "",
		},
		{
			name: "ConflictError",
			args: args{NewConflictError(fmt.Errorf("some other error"))},
			want: "",
		},
		{
			name: "NotFoundError",
			args: args{NewNotFoundError(fmt.Errorf("some other error"))},
			want: "",
		},
		{
			name: "mysql.ErrStoreRecord",
			args: args{NewNotFoundError(&mysql.ErrStoreRecord{})},
			want: "",
		},
		{
			name: "mysql.ErrGetRecord",
			args: args{NewNotFoundError(&mysql.ErrGetRecord{})},
			want: "",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := shouldReport(tt.args.err); got != tt.want {
				t.Errorf("shouldReport() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestConflictError_Unwrap(t *testing.T) {
	originalErr := errors.New("original error")
	conflictErr := NewConflictError(originalErr)

	unwrappedErr := errors.Unwrap(conflictErr)
	assert.Equal(t, originalErr, unwrappedErr)
}

func TestNewConflictError(t *testing.T) {
	originalErr := errors.New("original error")
	conflictErr := NewConflictError(originalErr)

	assert.Equal(t, "ConflictError: original error", conflictErr.Error())
	assert.Equal(t, originalErr.Error(), conflictErr.ClientFacingError())
}
