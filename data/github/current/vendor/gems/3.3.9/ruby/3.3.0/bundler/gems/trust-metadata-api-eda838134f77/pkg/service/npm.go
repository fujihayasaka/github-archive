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

type ctxNpmRequestIDKey string

const (
	// TODO: The following constants are placed here in the service package to avoid
	// a cyclical import issue. Ideally, these constants should reside in the transport package,
	// since they primarily deal with HTTPs and transport.
	// NPM
	NpmRequestID                         = "X-npm-request-id"
	NpmRequestIDLabel                    = "npm.request_id"
	NpmCtxKeyName     ctxNpmRequestIDKey = "ctx-npm-request-id"
	// tagged labels allow us to search them in Sentry
	TaggedNpmRequestIDLabel = "#" + NpmRequestIDLabel

	// SLSA Provenance Predicate Types
	PredicateSLSAProvenanceV02 = "https://slsa.dev/provenance/v0.2"
	PredicateSLSAProvenance    = "https://slsa.dev/provenance/v1"
)

/*
  NPM Service functions
*/

// CreateNPMAttestation creates an attestation in the database.
func (t *TMA) CreateNPMAttestation(ctx context.Context, pbundle *protobundle.Bundle, identifiers attestation.IdentifiersNPM) (*attestation.Record, error) {
	// set tracing for service layer
	ctx, span := o11y.NamedSpan(ctx, "Svc_CreateNPMAttestation")
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

	validateCtx, span := o11y.NamedSpan(ctx, "NPM_ValidateStatement")
	subjects, err := attestation.ValidateStatement(res.Statement)
	if err != nil {
		return nil, t.ReportError(validateCtx, NewBadRequestError(err))
	}
	span.End()

	// ensure that the Purl does not reference a different subject digest
	digestIsUnique, err := t.ValidatePurlSubjectDigestUniqueness(ctx, identifiers, subjects[0].SubjectDigest.String())
	if err != nil {
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("checking if digests match: %w", err)))
	}
	if !digestIsUnique {
		return nil, t.ReportError(ctx, NewConflictError(ErrDigestsMismatch))
	}

	ctx, span = o11y.NamedSpan(ctx, "StoreNPMAttestation")
	defer span.End()

	// create the TMA attestation bundle
	record, err := attestation.NewNPMAttestationRecord(pbundle, identifiers, subjects, res.Statement)
	if err != nil {
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to prepare attestation: %w", err)))
	}

	// set the created time
	creationTime := time.Now()
	record.CreatedAt = creationTime

	// store the NPM attestation in the database
	err = t.store.StoreNpmAttestation(ctx, record, bundle)
	if err != nil {
		if errors.Is(err, mysql.ErrDuplicateAttestation) {
			return nil, t.ReportError(ctx, NewConflictError(err))
		}
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to store attestation: %w", err)))
	}

	return record, nil
}

// GetNPMAttestations returns all attestations for given attestation identifiers from NPM
func (t *TMA) GetNPMAttestations(ctx context.Context, identifiers attestation.IdentifiersNPM) (*attestation.Records, error) {
	// set tracing for service layer
	ctx, span := o11y.NamedSpan(ctx, "Svc_GetNPMAttestations")
	defer span.End()

	// we need a purl to query NPM attestations
	if identifiers.Purl == "" {
		return nil, nil
	}

	attestations, err := t.store.GetAttestationsByPurl(ctx, identifiers, t.ReportError)
	if err != nil {
		if errors.Is(err, mysql.ErrAttestationNotFound) {
			return nil, t.ReportError(ctx, NewNotFoundError(err))
		}
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to retrieve attestation records: %w", err)))
	}

	return attestations, nil
}

// GetProvenanceAttestationSummary returns a summary of provenance for given attestation identifiers
func (t *TMA) GetProvenanceAttestationSummary(ctx context.Context, identifiers attestation.IdentifiersNPM) (*attestation.ProvenanceSummary, error) {
	// set tracing for service layer
	ctx, span := o11y.NamedSpan(ctx, "Svc_GetProvenanceAttestationSummary")
	defer span.End()

	predicateTypes := []string{PredicateSLSAProvenanceV02, PredicateSLSAProvenance}

	record, err := t.store.GetAttestationByPurlPredicateType(ctx, identifiers, predicateTypes)
	if err != nil {
		if errors.Is(err, mysql.ErrAttestationNotFound) {
			return nil, t.ReportError(ctx, NewNotFoundError(err))
		}
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to retrieve provenance: %w", err)))
	}

	if record == nil {
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to retrieve provenance: %w", err)))
	}

	se, err := newProtobufBundle(ctx, record.Bundle)
	if err != nil {
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to retrieve provenance: %w", err)))
	}

	provenanceSummary, err := attestation.NewProvenanceSummary(ctx, se)
	if err != nil {
		return nil, t.ReportError(ctx, NewInternalError(fmt.Errorf("failed to retrieve provenance: %w", err)))
	}
	return &provenanceSummary, nil
}

// ValidatePurlSubjectDigestUniqueness checks if the subject digest is unique for a given PURL
func (t *TMA) ValidatePurlSubjectDigestUniqueness(ctx context.Context, identifiers attestation.IdentifiersNPM, digest string) (bool, error) {
	// TODO: Revisit this logic. This enforces constraint that a given PURL must only have one subject digest.
	// Is this constraint necessary? It is valid for a PURL to reference multiple artifacts, each with their own digest.
	// Intended behavior should be documented. We should use MySQL to enforce this constraint to eliminate race condition.
	records, err := t.store.GetAttestationMySQLRecordsOnlyByPurl(ctx, identifiers)
	if err != nil {
		wrapped := fmt.Errorf("looking up attestation digest: %w", err)
		return false, wrapped
	}

	if records == nil {
		return true, nil
	}

	if len(records.Attestations) == 0 {
		return true, nil
	}

	// if an attestation associated with the purl exists
	// and the attestation's stored digest doesn't match the incoming digest
	// then do not store the attestation
	storedDigest := records.Attestations[0].SubjectDigest
	if storedDigest != "" && storedDigest != digest {
		return false, nil
	}
	return true, nil
}
