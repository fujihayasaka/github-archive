package mysql

import (
	"context"
	"database/sql"
	"errors"
	"sort"
	"sync"
	"time"

	"github.com/github/trust-metadata-api/pkg/attestation"
)

// InMemoryDatabase is an in-memory implementation of the Database interface.
type InMemoryDatabase struct {
	deleted  map[uint64]bool
	store    []attestation.Record
	subjects []attestation.Subject
	mu       sync.RWMutex
}

var _ Database = &InMemoryDatabase{}

// NewInMemoryDatabase creates a new instance of InMemoryDatabase.
func NewInMemoryDatabase() *InMemoryDatabase {
	return &InMemoryDatabase{
		store: []attestation.Record{},
	}
}

// StoreAttestation adds an attestation to the in-memory database.
func (d *InMemoryDatabase) StoreAttestation(_ context.Context, attestation *attestation.Record, _ *sql.Tx) (uint64, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.store = append(d.store, *attestation)

	return uint64(len(d.store)), nil
}

// StoreNPMAttestation adds an attestation to the in-memory database.
func (d *InMemoryDatabase) StoreNPMAttestation(_ context.Context, attestation *attestation.Record, _ *sql.Tx) (uint64, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.store = append(d.store, *attestation)

	return uint64(len(d.store)), nil
}

func (d *InMemoryDatabase) StoreAttestationSubjects(_ context.Context, _ uint64, subjects []attestation.Subject, _ *sql.Tx) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	d.subjects = append(d.subjects, subjects...)

	return nil
}

func (d *InMemoryDatabase) GetAttestationsByPurl(_ context.Context, identifiers attestation.IdentifiersNPM) ([]attestation.Record, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var attestations []attestation.Record

	for _, attestationRecord := range d.store {
		if attestationRecord.Purl == identifiers.Purl && attestationRecord.DomainID == identifiers.DomainID {
			attestations = append(attestations, attestationRecord)
		}
	}

	return attestations, nil
}

func (d *InMemoryDatabase) GetAttestationByPurlPredicateType(_ context.Context, identifiers attestation.IdentifiersNPM, predicateTypes []string) (*attestation.Record, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	// sort predicateTypes by DESC order
	sort.Slice(predicateTypes, func(i, j int) bool {
		return predicateTypes[i] > predicateTypes[j]
	})

	for _, predicateType := range predicateTypes {
		for _, attestationRecord := range d.store {
			if attestationRecord.Purl == identifiers.Purl && attestationRecord.DomainID == identifiers.DomainID && attestationRecord.PredicateType == predicateType {
				return &attestationRecord, nil
			}
		}
	}

	return nil, nil
}

// GetAttestationByRepository returns the attestation that matches the given ID.
func (d *InMemoryDatabase) GetAttestationByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	for _, attestationRecord := range d.store {
		if attestationRecord.ID == identifiers.ID && attestationRecord.DomainID == identifiers.DomainID && attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
			// Only return the record if it hasn't been marked as deleted
			if _, ok := d.deleted[attestationRecord.ID]; !ok {
				return &attestationRecord, nil
			}
		}
	}

	return nil, ErrAttestationNotFound
}

// ListAttestationsByOwnerSubjectDigest returns all attestations that match the given owner, repository, and subject digest.
func (d *InMemoryDatabase) ListAttestationsByOwnerSubjectDigest(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *Cursor) ([]attestation.Record, *attestation.PageInfo, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var attestations []attestation.Record

	for _, attestationRecord := range d.store {
		if attestationRecord.DomainID == identifiers.DomainID && attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID && attestationRecord.SubjectDigest == identifiers.SubjectDigest {
			// if the record is deleted, skip it
			if _, ok := d.deleted[attestationRecord.ID]; ok {
				continue
			}
			attestations = append(attestations, attestationRecord)
		}
	}

	return attestations, nil, nil
}

// ListAttestationsByOwnerSubjectDigests returns all attestations that match the given owner, repository, and subject digest.
func (d *InMemoryDatabase) ListAttestationsByOwnerSubjectDigests(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *Cursor) ([]attestation.Record, *attestation.PageInfo, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var attestations []attestation.Record

	for _, attestationRecord := range d.store {
		if attestationRecord.DomainID == identifiers.DomainID && attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
			for _, digest := range identifiers.SubjectDigests {
				if attestationRecord.SubjectDigest == digest {
					// if the record is deleted, skip it
					if _, ok := d.deleted[attestationRecord.ID]; ok {
						continue
					}
					attestations = append(attestations, attestationRecord)
				}
			}
		}
	}

	return attestations, nil, nil
}

// ListAttestationsByRepository returns all attestations that match the given owner and repository
func (d *InMemoryDatabase) ListAttestationsByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *Cursor) ([]attestation.Record, *attestation.PageInfo, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var attestations []attestation.Record

	for _, attestationRecord := range d.store {
		if attestationRecord.DomainID == identifiers.DomainID && attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
			// if the record is deleted, skip it
			if _, ok := d.deleted[attestationRecord.ID]; ok {
				continue
			}
			attestations = append(attestations, attestationRecord)
		}
	}

	return attestations, nil, nil
}

// ListAttestationSummariesByRepository returns all attestations that match the given owner and repository
func (d *InMemoryDatabase) ListAttestationSummariesByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *Cursor) ([]attestation.Record, *attestation.PageInfo, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var attestations []attestation.Record

	for _, attestationRecord := range d.store {
		if attestationRecord.DomainID == identifiers.DomainID && attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
			// if the record is deleted, skip it
			if _, ok := d.deleted[attestationRecord.ID]; ok {
				continue
			}
			attestations = append(attestations, attestationRecord)
		}
	}

	return attestations, nil, nil
}

// GetAttestationSummaryByRepository returns all attestations that match the given owner and repository
func (d *InMemoryDatabase) GetAttestationSummaryByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	for _, attestationRecord := range d.store {
		if attestationRecord.ID == identifiers.ID && attestationRecord.DomainID == identifiers.DomainID && attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
			// Only return the record if it hasn't been marked as deleted
			if _, ok := d.deleted[attestationRecord.ID]; !ok {
				return &attestationRecord, nil
			}
		}
	}

	return nil, ErrAttestationNotFound
}

func (d *InMemoryDatabase) DeleteAttestationsByID(_ context.Context, attestationIDs []uint64, _ time.Time) error {
	d.mu.Lock()
	defer d.mu.Unlock()

	for _, id := range attestationIDs {
		d.deleted[id] = true
	}
	return nil
}

// StoreRelease stores a release in the in-memory database.
func (d *InMemoryDatabase) StoreRelease(_ context.Context, attestationID uint64, record *attestation.Record, _ *sql.Tx) error {
	d.mu.Lock()
	defer d.mu.Unlock()
	if len(d.store) < int(attestationID) { //nolint:gosec
		return ErrAttestationNotFound
	}
	for i, a := range d.store {
		if int(attestationID) != i+1 && a.PredicateType == attestation.PredicateRelease && a.Tag == record.Tag && a.RepositoryID == record.RepositoryID && a.TenantID == record.TenantID { //nolint:gosec
			return errors.New("release already exists")
		}
	}
	for i := range d.store {
		if int(attestationID) == i+1 { //nolint:gosec
			d.store[i].Tag = record.Tag
		}
	}
	return nil
}

// Close is a no-op for InMemoryDatabase to implement the Database interface.
func (d *InMemoryDatabase) Close() error {
	return nil
}

func (d *InMemoryDatabase) Reset() {
	d.mu.RLock()
	defer d.mu.RUnlock()

	d.store = []attestation.Record{}
}

// GetDB returns the underlying database connection.
func (d *InMemoryDatabase) GetDB() *sql.DB {
	return nil
}
