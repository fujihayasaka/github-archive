package service

import (
	"context"
	"time"

	"github.com/github/go-exceptions"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/o11y"
	"github.com/github/trust-metadata-api/pkg/storage"

	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/sigstore/sigstore-go/pkg/verify"
)

const (
	MaxPageSize = 100
)

// TMA is the Trust Metadata API service.
type TMA struct {
	GitCommit   string
	verifier    *attestation.TMAVerifier
	reporter    *exceptions.Reporter
	store       storage.Store
	releasesSAN string
}

// NewTMA creates a new Trust Metadata API service.
func NewTMA(store storage.Store, commit string, verifier *attestation.TMAVerifier, reporter *exceptions.Reporter, releasesSAN string) *TMA {
	return &TMA{
		GitCommit:   commit,
		verifier:    verifier,
		reporter:    reporter,
		store:       store,
		releasesSAN: releasesSAN,
	}
}

// GetGitCommit returns the git commit of the current build.
func (t *TMA) GetGitCommit() string {
	return t.GitCommit
}

// VerifyBundle verifies an attestation bundle
func (t *TMA) VerifyBundle(ctx context.Context, bundle *sgbundle.Bundle) (*verify.VerificationResult, error) {
	_, span := o11y.NamedSpan(ctx, "VerifyBundle")
	defer span.End()

	return t.verifier.VerifyBundle(bundle)
}

func newProtobufBundle(ctx context.Context, pbundle *protobundle.Bundle) (*sgbundle.Bundle, error) {
	_, span := o11y.NamedSpan(ctx, "NewProtobufBundleAndValidate")
	defer span.End()

	return sgbundle.NewBundle(pbundle)
}

func generateTimeWithSecondsPrecision() time.Time {
	// Return a new Time object representing the current time truncated to seconds precision.
	// The Time object returned by Time.Now() has nanosecond precision
	// but when this time object is stored in MySQL, MySQL will round up the
	// nanosecond value, which can cause inconsistencies between the time we
	// create here and the time stored in and retrieved from MySQL
	return time.Now().Truncate(time.Second)
}
