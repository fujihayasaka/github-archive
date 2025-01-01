package storage

import (
	"context"
	"database/sql"
	"fmt"
	"sync"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/sigstore/sigstore-go/pkg/bundle"
)

type reportErrFunc = func(context.Context, error) error

// DatabaseEndpoints represents different ways to access the database
type DatabaseEndpoints struct {
	Primary mysql.Database
	Replica mysql.Database
}

func (s *DatabaseEndpoints) Close() {
	s.Primary.Close()
	s.Replica.Close()
}

type Store interface {
	GenerateSASUrl(ctx context.Context, record *attestation.Record) (string, error)
	// GitHub
	ListAttestationsBySubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.Cursor, reportErr reportErrFunc) (*attestation.Records, error)
	GetAttestationByRepository(context.Context, attestation.IdentifiersGitHub) (*attestation.Record, error)
	StoreGitHubAttestation(context.Context, *attestation.Record, *bundle.Bundle) error
	GetAttestationSummaryByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error)
	ListAttestationsByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.Cursor) (*attestation.Records, error)
	ListAttestationSummariesByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.Cursor) (*attestation.Records, error)
	// npm
	StoreNpmAttestation(context.Context, *attestation.Record, *bundle.Bundle) error
	GetAttestationByPurlPredicateType(ctx context.Context, identifiers attestation.IdentifiersNPM, predicateTypes []string) (*attestation.Record, error)
	GetAttestationsByPurl(ctx context.Context, identifiers attestation.IdentifiersNPM, reportErr reportErrFunc) (*attestation.Records, error)
	GetAttestationMySQLRecordsOnlyByPurl(ctx context.Context, identifiers attestation.IdentifiersNPM) (*attestation.Records, error)
}

type LiveStore struct {
	azBlobStorage azureblob.Client
	db            *DatabaseEndpoints
}

type StoreMySQLAttestationFunc = func(ctx context.Context, record *attestation.Record, tx *sql.Tx) (uint64, error)

func (s *LiveStore) StoreGitHubAttestation(ctx context.Context, record *attestation.Record, bundle *bundle.Bundle) error {
	return s.storeAttestation(ctx, s.db.Primary.StoreAttestation, record, bundle)
}

func (s *LiveStore) StoreNpmAttestation(ctx context.Context, record *attestation.Record, bundle *bundle.Bundle) error {
	return s.storeAttestation(ctx, s.db.Primary.StoreNPMAttestation, record, bundle)
}

func (s *LiveStore) storeAttestation(ctx context.Context, storeMySQLAttestation StoreMySQLAttestationFunc, record *attestation.Record, bundle *bundle.Bundle) error {
	tx, err := s.db.Primary.GetDB().BeginTx(ctx, nil)
	if err != nil {
		return mysql.ErrStoreRecord{}
	}
	// if tx.Commit() is called first, tx.Rollback() will no-op
	// nolint:errcheck
	defer tx.Rollback()

	// store the attestation in the attestations table
	storedID, err := storeMySQLAttestation(ctx, record, tx)
	if err != nil {
		return err
	}

	// store the attestation's subjects in the attestations_subjects table
	err = s.db.Primary.StoreAttestationSubjects(ctx, storedID, record.Subjects, tx)
	if err != nil {
		return err
	}

	// Populate the ID field of the stored attestation record
	record.ID = storedID

	// store the attestation in blob storage
	if err = s.azBlobStorage.StoreAttestation(ctx, *record, bundle); err != nil {
		errStoreBlob := fmt.Errorf("failed to store attestation in blob storage: %w", err)
		if err = tx.Rollback(); err != nil {
			return fmt.Errorf("rolling back MySQL transaction: %s: %w", err.Error(), errStoreBlob)
		}
		return errStoreBlob
	}

	if err := tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit MySQL attestation record insert: %w", err)
	}

	return nil
}

func (s *LiveStore) updateRecordsWithBundles(ctx context.Context, records []attestation.Record, reportErr reportErrFunc) ([]attestation.Record, error) {
	var updatedRecords = make([]attestation.Record, len(records))
	var wg sync.WaitGroup

	for i, record := range records {
		wg.Add(1)
		go func() {
			bundle, err := s.azBlobStorage.DownloadAttestation(ctx, record)
			if err != nil {
				// nolint:errcheck
				reportErr(ctx, fmt.Errorf("failed to download bundle from blob storage: %s", err.Error()))
			}

			record.Bundle = bundle

			// and generate a SAS URL for the bundle if requested
			sasURL, err := s.azBlobStorage.GenerateSASUrl(ctx, record)
			if err != nil {
				// nolint:errcheck
				reportErr(ctx, fmt.Errorf("failed to generate SAS URL for attestation bundle: %w", err))
			}

			record.SASUrl = sasURL

			updatedRecords[i] = record

			wg.Done()
		}()
	}

	wg.Wait()

	return updatedRecords, nil
}

func (s *LiveStore) GenerateSASUrl(ctx context.Context, record *attestation.Record) (string, error) {
	return s.azBlobStorage.GenerateSASUrl(ctx, *record)
}

func NewLiveStore(azBlobStorage azureblob.Client, db *DatabaseEndpoints) *LiveStore {
	return &LiveStore{
		azBlobStorage: azBlobStorage,
		db:            db,
	}
}
