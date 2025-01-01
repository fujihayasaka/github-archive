package storage

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob/bloberror"
	"github.com/github/go-exceptions"
	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage/azureblob"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/sigstore/sigstore-go/pkg/bundle"
	"golang.org/x/sync/errgroup"
)

// DatabaseEndpoints represents different ways to access the database
type DatabaseEndpoints struct {
	Primary *mysql.LiveDatabase
	Replica *mysql.LiveDatabase
}

func (s *DatabaseEndpoints) Close() {
	s.Primary.Close()
	s.Replica.Close()
}

type Store interface {
	// GitHub
	DeleteAttestationsByID(ctx context.Context, identifiers attestation.IdentifiersGitHubDelete, deletedAt time.Time) ([]attestation.Record, error)
	DeleteAttestationsBySubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHubDelete, deletedAt time.Time) ([]attestation.Record, error)
	GetBundlesByID(ctx context.Context, identifiers attestation.IdentifiersGitHubGet) (*attestation.Records, error)
	GetRepoIDs(ctx context.Context, identifiers attestation.IdentifiersGitHubGet) ([]attestation.Record, error)
	ListAttestationsBySubjectDigest(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.DescCursor) (*attestation.Records, error)
	ListAttestationsBySubjectDigests(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor *mysql.DescCursor) (*attestation.Records, error)
	GetAttestationByRepository(context.Context, attestation.IdentifiersGitHub) (*attestation.Record, error)
	StoreGitHubAttestation(context.Context, *attestation.Record, *bundle.Bundle) error
	StoreReleaseAttestation(context.Context, *attestation.Record, *bundle.Bundle) error
	GetAttestationSummaryByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error)
	ListAttestationSummariesByRepository(ctx context.Context, identifiers attestation.IdentifiersGitHub, cursor mysql.PageCursor) (*attestation.Records, error)
	// npm
	StoreNpmAttestation(context.Context, *attestation.Record, *bundle.Bundle) error
	GetAttestationByPurlPredicateType(ctx context.Context, identifiers attestation.IdentifiersNPM, predicateTypes []string) (*attestation.Record, error)
	GetAttestationsByPurl(ctx context.Context, identifiers attestation.IdentifiersNPM) (*attestation.Records, error)
	GetAttestationMySQLRecordsOnlyByPurl(ctx context.Context, identifiers attestation.IdentifiersNPM) (*attestation.Records, error)
}

type LiveStore struct {
	azBlobStorage azureblob.Client
	db            *DatabaseEndpoints
	reporter      *exceptions.Reporter
}

type StoreMySQLAttestationFunc = func(ctx context.Context, record *attestation.Record, tx *sql.Tx) (uint64, error)

func (s *LiveStore) StoreGitHubAttestation(ctx context.Context, record *attestation.Record, bundle *bundle.Bundle) error {
	return s.storeAttestation(ctx, s.db.Primary.StoreAttestation, record, bundle)
}

func (s *LiveStore) StoreReleaseAttestation(ctx context.Context, record *attestation.Record, bundle *bundle.Bundle) error {
	return s.storeAttestation(ctx, s.storeReleaseAttestation, record, bundle)
}

func (s *LiveStore) StoreNpmAttestation(ctx context.Context, record *attestation.Record, bundle *bundle.Bundle) error {
	return s.storeAttestation(ctx, s.db.Primary.StoreNPMAttestation, record, bundle)
}

func (s *LiveStore) storeAttestation(ctx context.Context, storeMySQLAttestation StoreMySQLAttestationFunc, record *attestation.Record, bundle *bundle.Bundle) error {
	tx, err := s.db.Primary.BeginTx(ctx, nil)
	if err != nil {
		return mysql.NewErrStoreRecord(err)
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

// storeReleaseAttestation stores release attestations -- first writing a record
// to the attestations table and then to the releases table
func (s *LiveStore) storeReleaseAttestation(ctx context.Context, record *attestation.Record, tx *sql.Tx) (uint64, error) {
	// store the attestation in the attestations table
	storedID, err := s.db.Primary.StoreAttestation(ctx, record, tx)
	if err != nil {
		return 0, err
	}
	// store record in releases table
	err = s.db.Primary.StoreRelease(ctx, storedID, record, tx)
	if err != nil {
		return 0, err
	}

	return storedID, nil
}

func (s *LiveStore) updateRecordsWithBundles(ctx context.Context, records []attestation.Record, generateSASURL bool) ([]attestation.Record, error) {
	var updatedRecords = make([]attestation.Record, len(records))
	g, ctx := errgroup.WithContext(ctx)

	for i, record := range records {
		g.Go(func() error {
			bundleBlob, err := s.azBlobStorage.DownloadAttestation(ctx, record)
			if err != nil {
				return fmt.Errorf("failed to download bundle from blob storage: %s", err.Error())
			}

			record.Bundle = bundleBlob

			if generateSASURL {
				// and generate a SAS URL for the bundle if requested
				sasURL, err := s.azBlobStorage.GenerateSASUrl(ctx, record)
				if err != nil {
					return fmt.Errorf("failed to generate SAS URL for attestation bundle: %w", err)
				}

				record.SASUrl = sasURL
			}

			updatedRecords[i] = record
			return nil
		})
	}

	if err := g.Wait(); err != nil {
		return nil, err
	}

	return updatedRecords, nil
}

func NewLiveStore(azBlobStorage azureblob.Client, db *DatabaseEndpoints, reporter *exceptions.Reporter) *LiveStore {
	return &LiveStore{
		azBlobStorage: azBlobStorage,
		db:            db,
		reporter:      reporter,
	}
}

func IsNotFoundErr(err error) bool {
	return errors.Is(err, mysql.ErrAttestationNotFound) || bloberror.HasCode(err, bloberror.BlobNotFound)
}
