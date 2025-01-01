package storage

import (
	"context"
	"fmt"

	"github.com/github/trust-metadata-api/pkg/attestation"
)

func (s *LiveStore) GetAttestationMySQLRecordsOnlyByPurl(ctx context.Context, identifiers attestation.IdentifiersNPM) (*attestation.Records, error) {
	attestations, err := s.db.Replica.GetAttestationsByPurl(ctx, identifiers)
	if err != nil {
		return nil, err
	}

	return &attestation.Records{
		Attestations: attestations,
	}, nil
}

func (s *LiveStore) GetAttestationsByPurl(ctx context.Context, identifiers attestation.IdentifiersNPM, reportErr reportErrFunc) (*attestation.Records, error) {
	attestations, err := s.db.Replica.GetAttestationsByPurl(ctx, identifiers)
	if err != nil {
		return nil, err
	}

	updatedRecords, err := s.updateRecordsWithBundles(ctx, attestations, reportErr)
	if err != nil {
		return nil, fmt.Errorf("failed to update records with bundles from blob storage: %w", err)
	}

	return &attestation.Records{
		Attestations: updatedRecords,
	}, nil
}

func (s *LiveStore) GetAttestationByPurlPredicateType(ctx context.Context, identifiers attestation.IdentifiersNPM, predicateTypes []string) (*attestation.Record, error) {
	record, err := s.db.Replica.GetAttestationByPurlPredicateType(ctx, identifiers, predicateTypes)
	if err != nil {
		return nil, err
	}

	if record == nil {
		return nil, nil
	}

	bundle, err := s.azBlobStorage.DownloadAttestation(ctx, *record)
	if err != nil {
		return nil, fmt.Errorf("failed to retrieve attestation bundle from blob storage: %w", err)
	}

	record.Bundle = bundle

	return record, nil
}
