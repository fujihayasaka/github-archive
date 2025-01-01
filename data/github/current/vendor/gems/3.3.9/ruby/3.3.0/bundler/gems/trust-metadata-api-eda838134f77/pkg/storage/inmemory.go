package storage

import (
	"context"
	"fmt"
	"sort"
	"sync"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/sigstore/sigstore-go/pkg/bundle"
)

// InMemoryStore is an in-memory implementation of the Store interface.
type InMemoryStore struct {
	store []attestation.Record
	mu    sync.RWMutex
}

var _ Store = &InMemoryStore{}

// NewInMemoryStore creates a new instance of InMemoryStore.
func NewInMemoryStore() *InMemoryStore {
	return &InMemoryStore{
		store: []attestation.Record{},
	}
}

// StoreGitHubAttestation stores GitHub attestations in the in-memory store.
func (s *InMemoryStore) StoreGitHubAttestation(_ context.Context, record *attestation.Record, bundle *bundle.Bundle) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, a := range s.store {
		if a.DomainID == record.DomainID && a.OwnerID == record.OwnerID && a.RepositoryID == record.RepositoryID {
			return mysql.ErrDuplicateAttestation
		}
	}

	record.Bundle = bundle.Bundle
	s.store = append(s.store, *record)

	return nil
}

// ListAttestationsBySubjectDigest fetches attestations from the in-memory store by GitHub identifiers.
func (s *InMemoryStore) ListAttestationsBySubjectDigest(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *mysql.Cursor, _ reportErrFunc) (*attestation.Records, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := attestation.Records{}

	for _, attestation := range s.store {
		if attestation.RepositoryID == identifiers.RepositoryID && attestation.DomainID == identifiers.DomainID {
			records.Attestations = append(records.Attestations, attestation)
		}
	}

	return &records, nil
}

// StoreNPMAttestation adds an attestation to the in-memory store.
func (s *InMemoryStore) StoreNpmAttestation(_ context.Context, record *attestation.Record, bundle *bundle.Bundle) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	for _, a := range s.store {
		if a.PredicateType == record.PredicateType && a.Purl == record.Purl {
			return mysql.ErrDuplicateAttestation
		}
	}

	record.Bundle = bundle.Bundle
	s.store = append(s.store, *record)

	return nil
}

// GetAttestationsByPurl fetches records from the in-memory store by purl.
func (s *InMemoryStore) GetAttestationsByPurl(_ context.Context, identifiers attestation.IdentifiersNPM, _ reportErrFunc) (*attestation.Records, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := &attestation.Records{}

	for _, attestation := range s.store {
		if attestation.Purl == identifiers.Purl && attestation.DomainID == identifiers.DomainID {
			records.Attestations = append(records.Attestations, attestation)
		}
	}

	if len(records.Attestations) == 0 {
		return nil, mysql.NewErrGetRecord(mysql.ErrAttestationNotFound)
	}

	return records, nil
}

func (s *InMemoryStore) GetAttestationMySQLRecordsOnlyByPurl(_ context.Context, identifiers attestation.IdentifiersNPM) (*attestation.Records, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := &attestation.Records{}

	for _, attestation := range s.store {
		if attestation.Purl == identifiers.Purl && attestation.DomainID == identifiers.DomainID {
			records.Attestations = append(records.Attestations, attestation)
		}
	}

	return records, nil
}

// GetAttestationsByPurl fetches a record from the in-memory store by purl and predicate type.
func (s *InMemoryStore) GetAttestationByPurlPredicateType(_ context.Context, identifiers attestation.IdentifiersNPM, predicateTypes []string) (*attestation.Record, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	// sort predicateTypes by DESC order
	sort.Slice(predicateTypes, func(i, j int) bool {
		return predicateTypes[i] > predicateTypes[j]
	})

	for _, predicateType := range predicateTypes {
		for _, attestation := range s.store {
			if attestation.Purl == identifiers.Purl && attestation.DomainID == identifiers.DomainID && attestation.PredicateType == predicateType {
				return &attestation, nil
			}
		}
	}

	return nil, nil
}

// GetAttestationByRepository returns the attestation that matches the given ID.
func (s *InMemoryStore) GetAttestationByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, attestation := range s.store {
		if attestation.ID == identifiers.ID && attestation.DomainID == identifiers.DomainID && attestation.OwnerID == identifiers.OwnerID && attestation.RepositoryID == identifiers.RepositoryID {
			attestation.SASUrl = fmt.Sprintf("some-signed-access-signature-for-%d", attestation.ID)
			return &attestation, nil
		}
	}

	return nil, mysql.ErrAttestationNotFound
}

// ListAttestationsByRepository returns all attestations that match the given owner and repository
func (s *InMemoryStore) ListAttestationsByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *mysql.Cursor) (*attestation.Records, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := &attestation.Records{}

	for _, attestation := range s.store {
		if attestation.DomainID == identifiers.DomainID && attestation.OwnerID == identifiers.OwnerID && attestation.RepositoryID == identifiers.RepositoryID {
			records.Attestations = append(records.Attestations, attestation)
		}
	}

	return records, nil
}

// ListAttestationSummariesByRepository returns all attestations that match the given owner and repository
func (s *InMemoryStore) ListAttestationSummariesByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *mysql.Cursor) (*attestation.Records, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := &attestation.Records{}

	for _, attestation := range s.store {
		if attestation.DomainID == identifiers.DomainID && attestation.OwnerID == identifiers.OwnerID && attestation.RepositoryID == identifiers.RepositoryID {
			records.Attestations = append(records.Attestations, attestation)
		}
	}

	return records, nil
}

// GetAttestationSummaryByRepository returns all attestations that match the given owner and repository
func (s *InMemoryStore) GetAttestationSummaryByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, attestation := range s.store {
		if attestation.ID == identifiers.ID && attestation.DomainID == identifiers.DomainID && attestation.OwnerID == identifiers.OwnerID && attestation.RepositoryID == identifiers.RepositoryID {
			return &attestation, nil
		}
	}

	return nil, mysql.ErrAttestationNotFound
}

func (s *InMemoryStore) GenerateSASUrl(_ context.Context, r *attestation.Record) (string, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, attestation := range s.store {
		if attestation.ID == r.ID && attestation.DomainID == r.DomainID && attestation.OwnerID == r.OwnerID && attestation.RepositoryID == r.RepositoryID {
			return fmt.Sprintf("some-signed-access-signature-for-%d", r.ID), nil
		}
	}

	return "", fmt.Errorf("failed to generate SAS")
}

// InMemoryFailStore

type FailInMemoryStore struct {
	InMemoryStore
}

// GetAttestationsByPurl fetches records from the in-memory store by purl.
func (s *FailInMemoryStore) GetAttestationsByPurl(context.Context, attestation.IdentifiersNPM, reportErrFunc) (*attestation.Records, error) {
	return nil, mysql.ErrAttestationNotFound
}

func (s *FailInMemoryStore) StoreGitHubAttestation(context.Context, *attestation.Record, *bundle.Bundle) error {
	return mysql.ErrStoreRecord{}
}

func (s *FailInMemoryStore) StoreNpmAttestation(context.Context, *attestation.Record, *bundle.Bundle) error {
	return mysql.ErrStoreRecord{}
}

type SASFailInMemoryStore struct {
	InMemoryStore
}

func (s *SASFailInMemoryStore) GenerateSASUrl(context.Context, *attestation.Record) (string, error) {
	return "", fmt.Errorf("failed to generate SAS")
}

type GitHubFetchFailInMemoryStore struct {
	InMemoryStore
}

func (s *GitHubFetchFailInMemoryStore) GetAttestationByRepository(context.Context, attestation.IdentifiersGitHub) (*attestation.Record, error) {
	return nil, mysql.ErrAttestationNotFound
}
