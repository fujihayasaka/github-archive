package storage

import (
	"context"
	"fmt"
	"time"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
)

// GetAttestationByRepository returns the attestation record for the given repository.
func (s *LiveStore) GetAttestationByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	record, err := s.db.Replica.GetAttestationByRepository(ctx, identifiers)
	if err != nil {
		return nil, err
	}

	bundle, err := s.azBlobStorage.DownloadAttestation(ctx, *record)
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve attestation bundle from blob storage: %w", err)
	}

	record.Bundle = bundle

	sasURL, err := s.azBlobStorage.GenerateSASUrl(ctx, *record)
	if err != nil {
		return nil, fmt.Errorf("failed to generate signed access signature for requested record: %w", err)
	}

	record.SASUrl = sasURL

	return record, nil
}

func (s *LiveStore) ListAttestationsBySubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.Cursor) (*attestation.Records, error) {
	var attestations []attestation.Record
	var pageInfo *attestation.PageInfo
	var err error

	// NOTE: this if else statement is temporary until batch fetching is fully implemented
	// if the subjectDigests field is not nil, call the method specifically for
	// fetching by multiple subject digests
	if len(identifiers.SubjectDigests) != 0 {
		attestations, pageInfo, err = s.db.Replica.ListAttestationsByOwnerSubjectDigests(ctx, identifiers, cursor)
	} else {
		// otherwise, fall back to the method for fetching by a single subject digest
		attestations, pageInfo, err = s.db.Replica.ListAttestationsByOwnerSubjectDigest(ctx, identifiers, cursor)
	}
	if err != nil {
		return nil, err
	}

	updated, err := s.updateRecordsWithBundles(ctx, attestations, true)
	if err != nil {
		return nil, fmt.Errorf("failed to update records with bundles from blob storage: %w", err)
	}

	return &attestation.Records{
		Attestations: updated,
		PageInfo:     pageInfo,
	}, nil
}

// GetAttestationSummaryByRepository returns the attestation summary for the given repository for the dotcom UI.
func (s *LiveStore) GetAttestationSummaryByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	return s.db.Replica.GetAttestationSummaryByRepository(ctx, identifiers)
}

// ListAttestationSummariesByRepository returns the attestation records for the given repository.
func (s *LiveStore) ListAttestationSummariesByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.Cursor) (*attestation.Records, error) {
	records, pageInfo, err := s.db.Replica.ListAttestationSummariesByRepository(ctx, identifiers, cursor)
	if err != nil {
		return nil, err
	}

	return &attestation.Records{
		Attestations: records,
		PageInfo:     pageInfo,
	}, nil
}

// DeleteAttestationsByID deletes the attestation records with the given IDs.
func (s *LiveStore) DeleteAttestationsByID(ctx context.Context, attestationIDs []uint64, deletedAt time.Time) error {
	return s.db.Primary.DeleteAttestationsByID(ctx, attestationIDs, deletedAt)
}
