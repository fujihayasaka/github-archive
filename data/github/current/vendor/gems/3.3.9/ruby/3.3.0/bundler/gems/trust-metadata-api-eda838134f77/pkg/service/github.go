package service

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/o11y"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
)

type ctxTenantIDKey string

const (
	// TODO: The following constants are placed here in the service package to avoid
	// a cyclical import issue. Ideally, these constants should reside in the transport package,
	// since they primarily deal with HTTPs and transport.
	TenantID                            = "X-GitHub-Tenant-ID"
	GitHubRequestIDLabel                = "gh.request_id"
	TenantIDCtxKeyName   ctxTenantIDKey = "ctx-tenant-request-id"
	// tagged labels allow us to search them in Sentry
	TaggedGitHubRequestIDLabel = "#" + GitHubRequestIDLabel
)

/*
  GitHub API Service Functions
*/

// CreateAttestation creates an attestation in the database.
func (t *TMA) CreateAttestation(ctx context.Context, pbundle *protobundle.Bundle, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	// set tracing for service layer
	ctx, span := o11y.NamedSpan(ctx, "Svc_CreateAttestation")
	defer span.End()

	// The following block of code:
	// 1. Parses the bundle from protobuf to the internal representation
	// 2. Verifies the bundle
	// 3. Extracts the statement from the bundle
	// 4. Validates the statement
	// 5. Extracts the subject digest from the statement for indexing
	//
	// TODO: Design abstraction for bundle verification and statement validation,
	// something like a TMAVerifier interface? Leaving this composable/decoupled
	// for now.
	bundle, err := newProtobufBundle(ctx, pbundle)
	if err != nil {
		return nil, t.ReportError(ctx, NewBadRequestError(err))
	}
	res, err := t.VerifyBundle(ctx, bundle)
	if err != nil {
		return nil, t.ReportError(ctx, NewBadRequestError(err))
	}

	validateCtx, span := o11y.NamedSpan(ctx, "GitHub_ValidateBundle")
	// verify the provenance statement with signing certificate OIDs
	err = attestation.ValidateCertificateIssuerIsFromGitHub(res.Signature.Certificate)
	if err != nil {
		return nil, t.ReportError(validateCtx, NewBadRequestError(err))
	}
	if identifiers.VerifyProvenanceStatement {
		err = attestation.VerifyProvenanceStatement(res)
		if err != nil {
			return nil, t.ReportError(ctx, NewBadRequestError(err))
		}
	}

	subjects, err := attestation.ValidateStatement(res.Statement)
	if err != nil {
		return nil, t.ReportError(validateCtx, NewBadRequestError(err))
	}
	span.End()

	ctx, span = o11y.NamedSpan(ctx, "GitHub_StoreBundle")
	defer span.End()

	// create the TMA attestation bundle
	record, err := attestation.NewGitHubAttestationRecord(pbundle, identifiers, subjects, res.Statement)
	if err != nil {
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to prepare attestation: %w", err)))
	}

	// set the created time
	creationTime := time.Now()
	record.CreatedAt = creationTime

	if err = t.store.StoreGitHubAttestation(ctx, record, bundle); err != nil {
		if errors.Is(err, mysql.ErrDuplicateAttestation) {
			return nil, t.ReportError(ctx, NewConflictError(err))
		}
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to store attestation: %w", err)))
	}

	return record, nil
}

// GetAttestation returns all attestations for given attestation identifiers for dotcom usecase
func (t *TMA) ListAttestationsBySubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.Cursor) (*attestation.Records, error) {
	// set tracing for service layer
	ctx, span := o11y.NamedSpan(ctx, "Svc_ListAttestationsBySubjectDigest")
	defer span.End()

	// MUST provide cursor for getting attestations from the database
	if cursor == nil {
		return nil, nil
	}

	records, err := t.store.ListAttestationsBySubjectDigest(ctx, identifiers, cursor, t.ReportError)
	if err != nil {
		if errors.Is(err, mysql.ErrAttestationNotFound) {
			return nil, t.ReportError(ctx, NewNotFoundError(err))
		}
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to retrieve attestation records: %w", err)))
	}

	return records, nil
}

// GetAttestationByRepository retrieves a single attestation by its ID.
func (t *TMA) GetAttestationByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	// set tracing for service layer
	ctx, span := o11y.NamedSpan(ctx, "Svc_GetAttestationByRepository")
	defer span.End()

	record, err := t.store.GetAttestationByRepository(ctx, identifiers)
	if err != nil {
		if errors.Is(err, mysql.ErrAttestationNotFound) {
			return nil, t.ReportError(ctx, NewNotFoundError(err))
		}
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to retrieve attestation record: %w", err)))
	}

	return record, nil
}

// GetAttestationSASByRepository returns a signed access signature (SAS) link
// so clients can retrieve an attestation blob directly from the blob store.
func (t *TMA) GetAttestationSASByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub) (string, error) {
	// set tracing for service layer
	ctx, span := o11y.NamedSpan(ctx, "Svc_GetAttestationSASByRepository")
	defer span.End()

	record, err := t.store.GetAttestationByRepository(ctx, identifiers)
	if err != nil {
		if errors.Is(err, mysql.ErrAttestationNotFound) {
			return "", t.ReportError(ctx, NewNotFoundError(err))
		}
		return "", t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to retrieve attestation record: %w", err)))
	}

	sas, err := t.store.GenerateSASUrl(ctx, record)
	if err != nil {
		return "", t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to generate signed access signature for requested record: %w", err)))
	}

	return sas, nil
}

// GetAttestationSummaryByRepository retrieves a single attestation summary by its ID.
func (t *TMA) GetAttestationSummaryByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	record, err := t.store.GetAttestationSummaryByRepository(ctx, identifiers)
	if err != nil {
		if errors.Is(err, mysql.ErrAttestationNotFound) {
			return nil, NewNotFoundError(err)
		}
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to retrieve attestation record: %w", err)))
	}

	return record, nil
}

// ListAttestationsByRepository returns all attestations for given attestation identifiers
func (t *TMA) ListAttestationsByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.Cursor) (*attestation.Records, error) {
	// set tracing for service layer
	ctx, span := o11y.NamedSpan(ctx, "Svc_ListAttestationsByRepository")
	defer span.End()

	if cursor == nil {
		return nil, nil
	}

	records, err := t.store.ListAttestationsByRepository(ctx, identifiers, cursor)
	if err != nil {
		if errors.Is(err, mysql.ErrAttestationNotFound) {
			return nil, t.ReportError(ctx, NewNotFoundError(err))
		}
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to retrieve attestation records: %w", err)))
	}

	return records, nil
}

// ListAttestationSummariesByRepository returns all attestations for given attestation identifiers
func (t *TMA) ListAttestationSummariesByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.Cursor) (*attestation.Records, error) {
	// set tracing for service layer
	ctx, span := o11y.NamedSpan(ctx, "Svc_ListAttestationSummariesByRepository")
	defer span.End()

	if cursor == nil {
		return nil, nil
	}

	records, err := t.store.ListAttestationSummariesByRepository(ctx, identifiers, cursor)
	if err != nil {
		if errors.Is(err, mysql.ErrAttestationNotFound) {
			return nil, t.ReportError(ctx, NewNotFoundError(err))
		}
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to retrieve attestation records: %w", err)))
	}

	return records, nil
}
