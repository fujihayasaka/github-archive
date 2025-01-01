package service

import (
	"context"
	"errors"
	"fmt"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/o11y"
	"github.com/github/trust-metadata-api/pkg/storage"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
)

/*
  GitHub API Service Functions
*/

// CreateAttestation creates an attestation in the database.
func (t *TMA) CreateAttestation(ctx context.Context, pbundle *protobundle.Bundle, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	// set tracing for service layer
	ctx, parentSpan := o11y.NamedSpan(ctx, "Svc_CreateAttestation")
	defer parentSpan.End()

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
		return nil, NewBadRequestError(err)
	}
	res, err := t.VerifyBundle(ctx, bundle)
	if err != nil {
		return nil, NewBadRequestError(err)
	}

	_, span := o11y.NamedSpan(ctx, "GitHub_ValidateBundle")
	// verify the provenance statement with signing certificate OIDs
	if err = attestation.ValidateCertificateIssuerIsFromGitHub(res.Signature.Certificate); err != nil {
		return nil, NewBadRequestError(err)
	}

	if err = attestation.VerifyProvenanceStatement(res); err != nil {
		return nil, NewBadRequestError(err)
	}

	// verify the release statement and extract the tag
	var tag string
	if res.Statement.PredicateType == attestation.PredicateRelease {
		if !identifiers.ExpectReleaseAttestation {
			return nil, NewBadRequestError(errors.New("release statement is not allowed"))
		}
		tag, err = attestation.VerifyReleaseStatement(res, t.releasesSAN)
		if err != nil {
			return nil, NewBadRequestError(err)
		}
	} else if identifiers.ExpectReleaseAttestation {
		return nil, NewBadRequestError(fmt.Errorf("this endpoint only supports release attestations with predicate type \"%s\"", attestation.PredicateRelease))
	}

	subjects, err := attestation.ValidateStatement(res.Statement)
	if err != nil {
		return nil, NewBadRequestError(err)
	}
	span.End()

	ctx, span = o11y.NamedSpan(ctx, "GitHub_StoreBundle")
	defer span.End()

	// create the TMA attestation bundle
	record, err := attestation.NewGitHubReleaseAttestationRecord(pbundle, identifiers, subjects, res.Statement, tag)
	if err != nil {
		return nil, NewInternalError(fmt.Errorf("failed to prepare attestation: %w", err))
	}

	// set the created time
	record.CreatedAt = generateTimeWithSecondsPrecision()

	if err = t.store.StoreGitHubAttestation(ctx, record, bundle); err != nil {
		if errors.Is(err, mysql.ErrReleaseAttestationConstraint) {
			return nil, NewConflictError(err)
		}
		return nil, NewInternalError(fmt.Errorf("failed to store attestation: %w", err))
	}

	return record, nil
}

// ListAttestationsBySubjectDigest returns all attestations for given GitHub attestation identifiers for dotcom usecase
func (t *TMA) ListAttestationsBySubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.Cursor) (*attestation.Records, error) {
	// set tracing for service layer
	ctx, span := o11y.NamedSpan(ctx, "Svc_ListAttestationsBySubjectDigest")
	defer span.End()

	// MUST provide cursor for getting attestations from the database
	if cursor == nil {
		return nil, nil
	}

	records, err := t.store.ListAttestationsBySubjectDigest(ctx, identifiers, cursor)
	if err != nil {
		if storage.IsNotFoundErr(err) {
			return nil, NewNotFoundError(err)
		}
		return nil, NewInternalError(fmt.Errorf("failed to retrieve attestation records: %w", err))
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
		if storage.IsNotFoundErr(err) {
			return nil, NewNotFoundError(err)
		}
		return nil, NewInternalError(fmt.Errorf("failed to retrieve attestation record: %w", err))
	}

	return record, nil
}

// GetAttestationSummaryByRepository retrieves a single attestation summary by its ID.
func (t *TMA) GetAttestationSummaryByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	record, err := t.store.GetAttestationSummaryByRepository(ctx, identifiers)
	if err != nil {
		if storage.IsNotFoundErr(err) {
			return nil, NewNotFoundError(err)
		}
		return nil, NewInternalError(fmt.Errorf("failed to retrieve attestation record: %w", err))
	}

	return record, nil
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
		if storage.IsNotFoundErr(err) {
			return nil, NewNotFoundError(err)
		}
		return nil, NewInternalError(fmt.Errorf("failed to retrieve attestation records: %w", err))
	}

	return records, nil
}

// DeleteAttestationsByID deletes attestations by their IDs
func (t *TMA) DeleteAttestationsByID(ctx context.Context, attestationIDs []uint64) error {
	ctx, span := o11y.NamedSpan(ctx, "Svc_DeleteAttestationsByID")
	defer span.End()

	deletedAt := generateTimeWithSecondsPrecision()
	return t.store.DeleteAttestationsByID(ctx, attestationIDs, deletedAt)
}
