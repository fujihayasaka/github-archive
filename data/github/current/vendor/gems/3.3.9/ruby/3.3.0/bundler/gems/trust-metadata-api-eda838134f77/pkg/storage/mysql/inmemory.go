package mysql

import (
	"context"
	"database/sql"
	"sort"
	"sync"

	"github.com/github/trust-metadata-api/pkg/attestation"
)

// InMemoryDatabase is an in-memory implementation of the Database interface.
type InMemoryDatabase struct {
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
	for _, a := range d.store {
		if a.PredicateType == attestation.PredicateType && a.Purl == attestation.Purl {
			return 0, ErrDuplicateAttestation
		}
	}
	d.store = append(d.store, *attestation)

	return uint64(len(d.store)), nil
}

// StoreNPMAttestation adds an attestation to the in-memory database.
func (d *InMemoryDatabase) StoreNPMAttestation(_ context.Context, attestation *attestation.Record, _ *sql.Tx) (uint64, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	for _, a := range d.store {
		if a.PredicateType == attestation.PredicateType && a.Purl == attestation.Purl {
			return 0, ErrDuplicateAttestation
		}
	}
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

	for _, attestation := range d.store {
		if attestation.Purl == identifiers.Purl && attestation.DomainID == identifiers.DomainID {
			attestations = append(attestations, attestation)
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
		for _, attestation := range d.store {
			if attestation.Purl == identifiers.Purl && attestation.DomainID == identifiers.DomainID && attestation.PredicateType == predicateType {
				return &attestation, nil
			}
		}
	}

	return nil, nil
}

// GetAttestationByRepository returns the attestation that matches the given ID.
func (d *InMemoryDatabase) GetAttestationByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	for _, attestation := range d.store {
		if attestation.ID == identifiers.ID && attestation.DomainID == identifiers.DomainID && attestation.OwnerID == identifiers.OwnerID && attestation.RepositoryID == identifiers.RepositoryID {
			return &attestation, nil
		}
	}

	return nil, ErrAttestationNotFound
}

// ListAttestationsByOwnerSubjectDigest returns all attestations that match the given owner, repository, and subject digest.
func (d *InMemoryDatabase) ListAttestationsByOwnerSubjectDigest(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *Cursor) ([]attestation.Record, *attestation.PageInfo, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var attestations []attestation.Record

	for _, attestation := range d.store {
		if attestation.DomainID == identifiers.DomainID && attestation.OwnerID == identifiers.OwnerID && attestation.RepositoryID == identifiers.RepositoryID && attestation.SubjectDigest == identifiers.SubjectDigest {
			attestations = append(attestations, attestation)
		}
	}

	return attestations, nil, nil
}

// ListAttestationsByRepository returns all attestations that match the given owner and repository
func (d *InMemoryDatabase) ListAttestationsByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *Cursor) ([]attestation.Record, *attestation.PageInfo, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var attestations []attestation.Record

	for _, attestation := range d.store {
		if attestation.DomainID == identifiers.DomainID && attestation.OwnerID == identifiers.OwnerID && attestation.RepositoryID == identifiers.RepositoryID {
			attestations = append(attestations, attestation)
		}
	}

	return attestations, nil, nil
}

// ListAttestationSummariesByRepository returns all attestations that match the given owner and repository
func (d *InMemoryDatabase) ListAttestationSummariesByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *Cursor) ([]attestation.Record, *attestation.PageInfo, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	var attestations []attestation.Record

	for _, attestation := range d.store {
		if attestation.DomainID == identifiers.DomainID && attestation.OwnerID == identifiers.OwnerID && attestation.RepositoryID == identifiers.RepositoryID {
			attestations = append(attestations, attestation)
		}
	}

	return attestations, nil, nil
}

// GetAttestationSummaryByRepository returns all attestations that match the given owner and repository
func (d *InMemoryDatabase) GetAttestationSummaryByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	d.mu.RLock()
	defer d.mu.RUnlock()

	for _, attestation := range d.store {
		if attestation.ID == identifiers.ID && attestation.DomainID == identifiers.DomainID && attestation.OwnerID == identifiers.OwnerID && attestation.RepositoryID == identifiers.RepositoryID {
			return &attestation, nil
		}
	}

	return nil, ErrAttestationNotFound
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
