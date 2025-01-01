package storage

import (
	"context"
	"fmt"
	"sort"
	"sync"
	"time"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/sigstore/sigstore-go/pkg/bundle"
)

// InMemoryStore is an in-memory implementation of the Store interface.
type InMemoryStore struct {
	deleted map[uint64]bool
	store   []attestation.Record
	mu      sync.RWMutex
}

var _ Store = &InMemoryStore{}

// NewInMemoryStore creates a new instance of InMemoryStore.
func NewInMemoryStore() *InMemoryStore {
	return &InMemoryStore{
		store:   []attestation.Record{},
		deleted: map[uint64]bool{},
	}
}

// StoreGitHubAttestation stores GitHub attestations in the in-memory store.
func (s *InMemoryStore) StoreGitHubAttestation(_ context.Context, record *attestation.Record, bundle *bundle.Bundle) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	record.Bundle = bundle.Bundle
	s.store = append(s.store, *record)

	return nil
}

// ListAttestationsBySubjectDigest fetches attestations from the in-memory store by GitHub identifiers.
func (s *InMemoryStore) ListAttestationsBySubjectDigest(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *mysql.Cursor) (*attestation.Records, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := attestation.Records{}

	for _, attestationRecord := range s.store {
		if attestationRecord.RepositoryID == identifiers.RepositoryID && attestationRecord.DomainID == identifiers.DomainID {
			// if the record is deleted, skip it
			if _, ok := s.deleted[attestationRecord.ID]; ok {
				continue
			}
			records.Attestations = append(records.Attestations, attestationRecord)
		}
	}

	return &records, nil
}

// StoreNpmAttestation adds an attestation to the in-memory store.
func (s *InMemoryStore) StoreNpmAttestation(_ context.Context, record *attestation.Record, bundle *bundle.Bundle) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	record.Bundle = bundle.Bundle
	s.store = append(s.store, *record)

	return nil
}

// GetAttestationsByPurl fetches records from the in-memory store by purl.
func (s *InMemoryStore) GetAttestationsByPurl(_ context.Context, identifiers attestation.IdentifiersNPM) (*attestation.Records, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := &attestation.Records{}

	for _, attestationRecord := range s.store {
		if attestationRecord.Purl == identifiers.Purl && attestationRecord.DomainID == identifiers.DomainID {
			records.Attestations = append(records.Attestations, attestationRecord)
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

	for _, attestationRecord := range s.store {
		if attestationRecord.Purl == identifiers.Purl && attestationRecord.DomainID == identifiers.DomainID {
			records.Attestations = append(records.Attestations, attestationRecord)
		}
	}

	return records, nil
}

// GetAttestationByPurlPredicateType fetches a record from the in-memory store by purl and predicate type.
func (s *InMemoryStore) GetAttestationByPurlPredicateType(_ context.Context, identifiers attestation.IdentifiersNPM, predicateTypes []string) (*attestation.Record, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	// sort predicateTypes by DESC order
	sort.Slice(predicateTypes, func(i, j int) bool {
		return predicateTypes[i] > predicateTypes[j]
	})

	for _, predicateType := range predicateTypes {
		for _, attestationRecord := range s.store {
			if attestationRecord.Purl == identifiers.Purl && attestationRecord.DomainID == identifiers.DomainID && attestationRecord.PredicateType == predicateType {
				return &attestationRecord, nil
			}
		}
	}

	return nil, nil
}

// GetAttestationByRepository returns the attestation that matches the given ID.
func (s *InMemoryStore) GetAttestationByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, attestationRecord := range s.store {
		if attestationRecord.ID == identifiers.ID && attestationRecord.DomainID == identifiers.DomainID && attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
			// if the record is deleted, skip it
			if _, ok := s.deleted[attestationRecord.ID]; ok {
				continue
			}

			attestationRecord.SASUrl = fmt.Sprintf("some-signed-access-signature-for-%d", attestationRecord.ID)
			return &attestationRecord, nil
		}
	}

	return nil, mysql.ErrAttestationNotFound
}

// ListAttestationsByRepository returns all attestations that match the given owner and repository
func (s *InMemoryStore) ListAttestationsByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *mysql.Cursor) (*attestation.Records, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := &attestation.Records{}

	for _, attestationRecord := range s.store {
		if attestationRecord.DomainID == identifiers.DomainID && attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
			// if the record is deleted, skip it
			if _, ok := s.deleted[attestationRecord.ID]; ok {
				continue
			}
			records.Attestations = append(records.Attestations, attestationRecord)
		}
	}

	return records, nil
}

// ListAttestationSummariesByRepository returns all attestations that match the given owner and repository
func (s *InMemoryStore) ListAttestationSummariesByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *mysql.Cursor) (*attestation.Records, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := &attestation.Records{}

	for _, attestationRecord := range s.store {
		if attestationRecord.DomainID == identifiers.DomainID && attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
			// if the record is deleted, skip it
			if _, ok := s.deleted[attestationRecord.ID]; ok {
				continue
			}
			records.Attestations = append(records.Attestations, attestationRecord)
		}
	}

	return records, nil
}

// GetAttestationSummaryByRepository returns all attestations that match the given owner and repository
func (s *InMemoryStore) GetAttestationSummaryByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub) (*attestation.Record, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	for _, attestationRecord := range s.store {
		if attestationRecord.ID == identifiers.ID && attestationRecord.DomainID == identifiers.DomainID && attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
			// if the record is not deleted, return it
			if _, ok := s.deleted[attestationRecord.ID]; !ok {
				return &attestationRecord, nil
			}
		}
	}

	return nil, mysql.ErrAttestationNotFound
}

func (s *InMemoryStore) DeleteAttestationsByID(_ context.Context, attestationIDs []uint64, _ time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	for _, id := range attestationIDs {
		s.deleted[id] = true
	}

	return nil
}

// InMemoryFailStore

type FailInMemoryStore struct {
	InMemoryStore
}

// GetAttestationsByPurl fetches records from the in-memory store by purl.
func (s *FailInMemoryStore) GetAttestationsByPurl(context.Context, attestation.IdentifiersNPM) (*attestation.Records, error) {
	return nil, mysql.ErrAttestationNotFound
}

func (s *FailInMemoryStore) StoreGitHubAttestation(context.Context, *attestation.Record, *bundle.Bundle) error {
	return &mysql.ErrStoreRecord{}
}

func (s *FailInMemoryStore) StoreNpmAttestation(context.Context, *attestation.Record, *bundle.Bundle) error {
	return &mysql.ErrStoreRecord{}
}

type SASFailInMemoryStore struct {
	InMemoryStore
}

type GitHubFetchFailInMemoryStore struct {
	InMemoryStore
}

func (s *GitHubFetchFailInMemoryStore) GetAttestationByRepository(context.Context, attestation.IdentifiersGitHub) (*attestation.Record, error) {
	return nil, mysql.ErrAttestationNotFound
}
