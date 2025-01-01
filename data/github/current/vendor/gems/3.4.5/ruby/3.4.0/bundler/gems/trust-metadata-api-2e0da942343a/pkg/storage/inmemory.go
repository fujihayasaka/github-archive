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
	deleted  map[uint64]bool
	store    []attestation.Record
	releases []attestation.Record
	mu       sync.RWMutex
}

var _ Store = &InMemoryStore{}

// NewInMemoryStore creates a new instance of InMemoryStore.
func NewInMemoryStore() *InMemoryStore {
	return &InMemoryStore{
		store:    []attestation.Record{},
		deleted:  map[uint64]bool{},
		releases: []attestation.Record{},
	}
}

// ReleaseCount returns the number of releases in the in-memory store.
func (s *InMemoryStore) ReleaseCount() int {
	s.mu.RLock()
	defer s.mu.RUnlock()

	return len(s.releases)
}

// StoreGitHubAttestation stores GitHub attestations in the in-memory store.
func (s *InMemoryStore) StoreGitHubAttestation(_ context.Context, record *attestation.Record, bundle *bundle.Bundle) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	record.Bundle = bundle.Bundle
	s.store = append(s.store, *record)

	return nil
}

func (s *InMemoryStore) StoreReleaseAttestation(_ context.Context, record *attestation.Record, bundle *bundle.Bundle) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	record.Bundle = bundle.Bundle
	s.store = append(s.store, *record)
	s.releases = append(s.releases, *record)

	return nil
}

func (s *InMemoryStore) GetBundlesByID(_ context.Context, identifiers attestation.IdentifiersGitHubGet) (*attestation.Records, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := &attestation.Records{}
	for _, attestationRecord := range s.store {
		for _, id := range identifiers.AttestationIDs {
			if attestationRecord.ID == id && attestationRecord.DomainID == identifiers.DomainID && *attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
				// Only return the record if it hasn't been marked as deleted
				if _, ok := s.deleted[attestationRecord.ID]; !ok {
					records.Attestations = append(records.Attestations, attestationRecord)
				}
			}
		}
	}

	return records, nil
}

func (s *InMemoryStore) GetRepoIDs(_ context.Context, identifiers attestation.IdentifiersGitHubGet) ([]attestation.Record, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := []attestation.Record{}
	for _, attestationRecord := range s.store {
		if len(identifiers.AttestationIDs) == 0 && len(identifiers.SubjectDigests) == 0 {
			return nil, fmt.Errorf("no IDs or subject digests provided")
		}
		if len(identifiers.AttestationIDs) != 0 && len(identifiers.SubjectDigests) != 0 {
			return nil, fmt.Errorf("both IDs and subject digests provided")
		}
		if len(identifiers.AttestationIDs) != 0 {
			for _, id := range identifiers.AttestationIDs {
				if attestationRecord.ID == id && attestationRecord.DomainID == identifiers.DomainID && *attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
					// Only return the record if it hasn't been marked as deleted
					if _, ok := s.deleted[attestationRecord.ID]; !ok {
						records = append(records, attestationRecord)
					}
				}
			}
		} else {
			for _, sd := range identifiers.SubjectDigests {
				if attestationRecord.SubjectDigest == sd && attestationRecord.DomainID == identifiers.DomainID && *attestationRecord.OwnerID == identifiers.OwnerID && attestationRecord.RepositoryID == identifiers.RepositoryID {
					// Only return the record if it hasn't been marked as deleted
					if _, ok := s.deleted[attestationRecord.ID]; !ok {
						records = append(records, attestationRecord)
					}
				}
			}
		}
	}

	return records, nil
}

// ListAttestationsBySubjectDigest fetches attestations from the in-memory store by GitHub identifiers.
func (s *InMemoryStore) ListAttestationsBySubjectDigest(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *mysql.DescCursor) (*attestation.Records, error) {
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

func (s *InMemoryStore) ListAttestationsBySubjectDigests(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *mysql.DescCursor) (*attestation.Records, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	records := attestation.Records{}

	for _, attestationRecord := range s.store {
		if attestationRecord.RepositoryID == identifiers.RepositoryID && attestationRecord.DomainID == identifiers.DomainID {
			for _, sd := range identifiers.SubjectDigests {
				if attestationRecord.SubjectDigest == sd {
					// if the record is deleted, skip it
					if _, ok := s.deleted[attestationRecord.ID]; ok {
						continue
					}
					records.Attestations = append(records.Attestations, attestationRecord)
				}
			}
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
func (s *InMemoryStore) ListAttestationsByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub, _ *mysql.DescCursor) (*attestation.Records, error) {
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
func (s *InMemoryStore) ListAttestationSummariesByRepository(_ context.Context, identifiers attestation.IdentifiersGitHub, _ mysql.PageCursor) (*attestation.Records, error) {
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

func (s *InMemoryStore) DeleteAttestationsByID(_ context.Context, i attestation.IdentifiersGitHubDelete, _ time.Time) ([]attestation.Record, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	deleteRecords := []attestation.Record{}
	for _, id := range i.AttestationIDs {
		s.deleted[id] = true
	}
	for _, attestationRecord := range s.store {
		for _, id := range i.AttestationIDs {
			if attestationRecord.ID == id {
				deleteRecords = append(deleteRecords, attestationRecord)
			}
		}
	}

	return deleteRecords, nil
}

func (s *InMemoryStore) DeleteAttestationsBySubjectDigest(_ context.Context, identifiers attestation.IdentifiersGitHubDelete, _ time.Time) ([]attestation.Record, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	for _, attestationRecord := range s.store {
		if attestationRecord.DomainID == identifiers.DomainID && *attestationRecord.OwnerID == identifiers.OwnerID {
			for _, sd := range identifiers.SubjectDigests {
				if attestationRecord.SubjectDigest == sd {
					s.deleted[attestationRecord.ID] = true
				}
			}
		}
	}
	return nil, nil
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
