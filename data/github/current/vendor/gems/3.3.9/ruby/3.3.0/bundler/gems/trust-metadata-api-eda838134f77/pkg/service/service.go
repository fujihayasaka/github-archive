package service

import (
	"context"
	"errors"

	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/o11y"
	"github.com/github/trust-metadata-api/pkg/storage"

	exceptions "github.com/github/go-exceptions"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/sigstore/sigstore-go/pkg/verify"
)

/*
  NOTE: make sure to wrap all errors with t.ReportError() when returning errors from this file
*/

const (
	MaxPageSize  = 100
	ErrTypeLabel = "http.request.error_type"
)

// An interface is defined here so we can create
// structs for testing that fulfill the interface
type TMAService interface {
	GetGitCommit() string
	ReportError(context.Context, error) error
	VerifyBundle(ctx context.Context, bundle *sgbundle.Bundle) (*verify.VerificationResult, error)
	// NPM
	CreateNPMAttestation(context.Context, *protobundle.Bundle, attestation.IdentifiersNPM) (*attestation.Record, error)
	GetProvenanceAttestationSummary(context.Context, attestation.IdentifiersNPM) (*attestation.ProvenanceSummary, error)
	GetNPMAttestations(context.Context, attestation.IdentifiersNPM) (*attestation.Records, error)
	ValidatePurlSubjectDigestUniqueness(ctx context.Context, identifiers attestation.IdentifiersNPM, digest string) (bool, error)
	// GitHubAPI
	CreateAttestation(context.Context, *protobundle.Bundle, attestation.IdentifiersGitHub) (*attestation.Record, error)
	ListAttestationsBySubjectDigest(context.Context, attestation.IdentifiersGitHub, *mysql.Cursor) (*attestation.Records, error)
	GetAttestationByRepository(context.Context, attestation.IdentifiersGitHub) (*attestation.Record, error)
	ListAttestationsByRepository(context.Context, attestation.IdentifiersGitHub, *mysql.Cursor) (*attestation.Records, error)
	ListAttestationSummariesByRepository(context.Context, attestation.IdentifiersGitHub, *mysql.Cursor) (*attestation.Records, error)
	GetAttestationSummaryByRepository(context.Context, attestation.IdentifiersGitHub) (*attestation.Record, error)
}

// TMA is the Trust Metadata API service.
type TMA struct {
	GitCommit string
	verifier  *attestation.TMAVerifier
	reporter  *exceptions.Reporter
	store     storage.Store
}

// NewTMA creates a new Trust Metadata API service.
func NewTMA(store storage.Store, commit string, verifier *attestation.TMAVerifier, reporter *exceptions.Reporter) (*TMA, error) {
	return &TMA{
		GitCommit: commit,
		verifier:  verifier,
		reporter:  reporter,
		store:     store,
	}, nil
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

// ReportError determines how to handle InternalErrors when reporting to Sentry.
func (t *TMA) ReportError(ctx context.Context, err error) error {
	if t.reporter == nil {
		return err
	}
	// This is reporting the error to Sentry
	if errType := shouldReport(err); errType != "" {
		fields := map[string]string{}
		fields[ErrTypeLabel] = errType
		fields[TaggedGitHubRequestIDLabel] = requestid.GetGitHubRequestID(ctx)

		if npmReqID, ok := ctx.Value(NpmCtxKeyName).(string); ok {
			fields[TaggedNpmRequestIDLabel] = npmReqID
		}
		_ = t.reporter.Report(context.Background(), err, fields)
	}

	return err
}

func shouldReport(err error) string {
	// General Internal errors
	var errInternal InternalError
	if errors.As(err, &errInternal) {
		// We need to unwrap the error to check the storage error.
		unwrapError := errInternal.Unwrap()

		// MySQL connection errors
		var errMySQLConn *mysql.ErrMySQLConn
		var errMySQLClose *mysql.ErrMySQLClose
		if errors.As(unwrapError, &errMySQLConn) || errors.As(unwrapError, &errMySQLClose) {
			return "mysql_connection"
		}

		// SQLC conversion errors
		var errConvertFromSQLC *mysql.ErrConvertFromSQLC
		var errConvertToSQLC *mysql.ErrConvertToSQLC
		if errors.As(unwrapError, &errConvertFromSQLC) || errors.As(unwrapError, &errConvertToSQLC) {
			return "sqlc_conversion"
		}

		// Azure blob storage errors
		var errBlobStorageDownload *azureblob.ErrBlobDownloadFailed
		var errBlobStorageUpload *azureblob.ErrBlobUploadFailed
		if errors.As(unwrapError, &errBlobStorageDownload) {
			return "blob_storage_download"
		}
		if errors.As(unwrapError, &errBlobStorageUpload) {
			return "blob_storage_upload"
		}

		return "internal"
	}

	return ""
}

func newProtobufBundle(ctx context.Context, pbundle *protobundle.Bundle) (*sgbundle.Bundle, error) {
	_, span := o11y.NamedSpan(ctx, "NewProtobufBundleAndValidate")
	defer span.End()

	return sgbundle.NewBundle(pbundle)
}
