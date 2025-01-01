package storage

import (
	"context"
	"fmt"

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

	sasURL, err := s.GenerateSASUrl(ctx, record)
	if err != nil {
		return nil, fmt.Errorf("failed to generate signed access signature for requested record: %w", err)
	}

	record.SASUrl = sasURL

	return record, nil
}

// ListAttestationsBySubjectDigest returns the attestation records for the given subject digest.
func (s *LiveStore) ListAttestationsBySubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.Cursor, reportErr reportErrFunc) (*attestation.Records, error) {
	attestations, pageInfo, err := s.db.Replica.ListAttestationsByOwnerSubjectDigest(ctx, identifiers, cursor)

	if err != nil {
		return nil, err
	}

	updated, err := s.updateRecordsWithBundles(ctx, attestations, reportErr)
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

// ListAttestationsByRepository returns the attestation records for the given repository.
func (s *LiveStore) ListAttestationsByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.Cursor) (*attestation.Records, error) {
	records, pageInfo, err := s.db.Replica.ListAttestationsByRepository(ctx, identifiers, cursor)
	if err != nil {
		return nil, err
	}

	return &attestation.Records{
		Attestations: records,
		PageInfo:     pageInfo,
	}, nil
}

// ListAttestationsByRepository returns the attestation records for the given repository.
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
