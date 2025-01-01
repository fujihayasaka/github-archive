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

func (s *LiveStore) GetBundlesByID(ctx context.Context, identifiers attestation.IdentifiersGitHubGet) (*attestation.Records, error) {
	attestations, err := s.db.Replica.ListBundleIdentifiersByAttestationID(ctx, identifiers)
	if err != nil {
		return nil, err
	}

	updated, err := s.updateRecordsWithBundles(ctx, attestations, false)
	if err != nil {
		return nil, fmt.Errorf("failed to update records with bundles from blob storage: %w", err)
	}

	return &attestation.Records{
		Attestations: updated,
	}, nil
}

func (s *LiveStore) GetRepoIDs(ctx context.Context, identifiers attestation.IdentifiersGitHubGet) ([]attestation.Record, error) {
	switch {
	case len(identifiers.AttestationIDs) != 0:
		return s.db.Replica.ListBundleIdentifiersByAttestationID(ctx, identifiers)
	case len(identifiers.SubjectDigests) != 0:
		return s.db.Replica.ListBundleIdentifiersBySubjectDigest(ctx, identifiers)
	default:
		return nil, fmt.Errorf("no IDs or subject digests provided")
	}
}

func (s *LiveStore) ListAttestationsBySubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.DescCursor) (*attestation.Records, error) {
	attestations, pageInfo, err := s.db.Replica.ListAttestationsByOwnerSubjectDigest(ctx, identifiers, cursor)
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

func (s *LiveStore) ListAttestationsBySubjectDigests(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.DescCursor) (*attestation.Records, error) {
	records, pageInfo, err := s.db.Replica.ListAttestationsByOwnerSubjectDigests(ctx, identifiers, cursor)
	if err != nil {
		return nil, err
	}

	updated, err := s.updateRecordsWithBundles(ctx, records, true)
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
func (s *LiveStore) ListAttestationSummariesByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor mysql.PageCursor) (*attestation.Records, error) {
	var records []attestation.Record
	var pageInfo *attestation.PageInfo
	var err error

	// Check if the filters are not set. If they are not set, use the simplified query
	// called in the ListAttestationSummariesByRepository database method
	predicateType := identifiers.PredicateType
	partialSubjectName := identifiers.SubjectName
	created := identifiers.Created
	if predicateType == "" && partialSubjectName == "" && created.Empty() {
		records, pageInfo, err = s.db.Replica.ListAttestationSummariesByRepository(ctx, identifiers, cursor)
	} else {
		records, pageInfo, err = s.db.Replica.ListAttestationSummariesByRepositoryWithFilters(ctx, identifiers, cursor)
	}
	if err != nil {
		return nil, err
	}

	totalCount := int64(0)
	if len(records) > 0 {
		totalCount = records[0].TotalCount
	}

	return &attestation.Records{
		Attestations: records,
		PageInfo:     pageInfo,
		TotalCount:   totalCount,
	}, nil
}

// DeleteAttestationsByID deletes the attestation records with the given IDs.
func (s *LiveStore) DeleteAttestationsByID(ctx context.Context, identifiers attestation.IdentifiersGitHubDelete, deletedAt time.Time) ([]attestation.Record, error) {
	return s.db.Primary.DeleteAttestationsByID(ctx, identifiers, deletedAt)
}

// DeleteAttestationsBySubject deletes the attestation records with subject digests.
func (s *LiveStore) DeleteAttestationsBySubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHubDelete, deletedAt time.Time) ([]attestation.Record, error) {
	return s.db.Primary.DeleteAttestationsBySubjectDigest(ctx, identifiers, deletedAt)
}
