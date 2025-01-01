package service

import (
	"context"
	"errors"
	"fmt"
	"testing"

	"github.com/github/trust-metadata-api/test/data"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
)

const (
	TestPurl      = "pkg:npm/foo/bar@12.3.1"
	SubjectDigest = "sha256:00522a5ecf4f877384d6781bea67a9b3827209cb6787e6ddceb8fd792a5f416c"
	SubjectName   = "foo/bar"
)

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
