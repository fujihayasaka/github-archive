//go:build integration

package service

import (
	"context"
	"fmt"
	"math/rand"
	"testing"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/testing/data"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
)

func TestStoreGetAttestationsByRepository(t *testing.T) {
	ctx := context.Background()
	tmaService, cleanUp := NewTMAWithLocalDockerStorage(t)
	defer cleanUp(t)

	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     2,
	}
	testBundle := data.SigstoreBundleFromGenerateBuildProvenance(t)

	record, err := tmaService.CreateAttestation(ctx, testBundle, identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)
	assert.Equal(t, identifiers.DomainID, record.DomainID)
	assert.Equal(t, identifiers.OwnerID, record.OwnerID)
	assert.Equal(t, identifiers.RepositoryID, record.RepositoryID)

	// check that the GetAttestationByRepository method returns the bundle and
	// record metadata as expected
	identifiers.ID = record.ID
	record, err = tmaService.GetAttestationByRepository(ctx, identifiers)
	assert.NoError(t, err)
	assert.Equal(t, testBundle, record.Bundle)
	assert.Equal(t, identifiers.DomainID, record.DomainID)
	assert.Equal(t, identifiers.OwnerID, record.OwnerID)
	assert.Equal(t, identifiers.RepositoryID, record.RepositoryID)
	assert.NotZero(t, record.SASUrl)
}

func TestStoreGetAttestationSummaryByRepository(t *testing.T) {
	ctx := context.Background()
	tmaService, cleanUp := NewTMAWithLocalDockerStorage(t)
	defer cleanUp(t)

	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     2,
	}
	testBundle := data.SigstoreJs300ProtoBundle(t)

	record, err := tmaService.CreateAttestation(ctx, testBundle, identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)
	assert.Equal(t, identifiers.DomainID, record.DomainID)
	assert.Equal(t, identifiers.OwnerID, record.OwnerID)
	assert.Equal(t, identifiers.RepositoryID, record.RepositoryID)

	// check that the GetAttestationSummaryByRepository method returns the bundle and
	// record metadata as expected
	identifiers.ID = record.ID
	record, err = tmaService.GetAttestationSummaryByRepository(ctx, identifiers)
	assert.NoError(t, err)

	assert.NotNil(t, record.ID)
	assert.Equal(t, identifiers.OwnerID, record.OwnerID)
	assert.Equal(t, identifiers.RepositoryID, record.RepositoryID)
	assert.NotNil(t, record.Certificate)
	assert.NotNil(t, record.CreatedAt)
	assert.Equal(t, "pkg:npm/sigstore@2.2.0", record.Subjects[0].Name)
	assert.NotEmpty(t, record.Subjects[0].SubjectDigest.Digest)
	assert.NotEmpty(t, record.Subjects)
}

func TestStoreListAttestationSummariesByRepository(t *testing.T) {
	ctx := context.Background()
	tmaService, cleanUp := NewTMAWithLocalDockerStorage(t)
	defer cleanUp(t)

	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	identifiers := attestation.IdentifiersGitHub{
		OwnerID:      &ownerID,
		RepositoryID: &repoID,
		DomainID:     2,
	}
	testBundle := data.SigstoreBundleFromGenerateBuildProvenance(t)

	record, err := tmaService.CreateAttestation(ctx, testBundle, identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)
	assert.Equal(t, identifiers.DomainID, record.DomainID)
	assert.Equal(t, identifiers.OwnerID, record.OwnerID)
	assert.Equal(t, identifiers.RepositoryID, record.RepositoryID)

	cursor := mysql.Cursor{
		PerPage: 10,
	}

	// check that the ListAttestationSummariesByRepository method returns the record metadata as expected
	records, err := tmaService.ListAttestationSummariesByRepository(ctx, identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records.Attestations, 1)
	assert.Equal(t, identifiers.OwnerID, records.Attestations[0].OwnerID)
	assert.Equal(t, identifiers.RepositoryID, records.Attestations[0].RepositoryID)
	assert.Equal(t, uint64(1), records.Attestations[0].SubjectCount)
}

func TestListAttestationsBySubjectDigest(t *testing.T) {
	ctx := context.Background()
	tmaService, cleanUp := NewTMAWithLocalDockerStorage(t)
	defer cleanUp(t)

	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	subjectDigests := []string{}
	bundles := []*protobundle.Bundle{data.SigstoreBundleFromGenerateBuildProvenance(t), data.SigstoreJs300ProtoBundle(t)}
	for _, b := range bundles {
		identifiers := attestation.IdentifiersGitHub{
			OwnerID:      &ownerID,
			RepositoryID: &repoID,
			DomainID:     2,
		}
		_, err := tmaService.CreateAttestation(ctx, b, identifiers)
		assert.NoError(t, err)

		sgb, err := sgbundle.NewBundle(b)
		assert.NoError(t, err)
		envelope, err := sgb.Envelope()
		assert.NoError(t, err)
		statement, err := envelope.Statement()
		assert.NoError(t, err)

		for _, sub := range statement.Subject {
			var alg, digest string
			// nolint:revive
			for alg, digest = range sub.Digest {
			}
			subjectDigests = append(subjectDigests, fmt.Sprintf("%s:%s", alg, digest))
		}
	}

	cursor := mysql.Cursor{
		PerPage: 10,
	}

	// First, fetch attestations by a list of subject digests
	identifiers := attestation.IdentifiersGitHub{
		OwnerID:        &ownerID,
		RepositoryID:   &repoID,
		DomainID:       2,
		SubjectDigests: subjectDigests,
	}
	records, err := tmaService.ListAttestationsBySubjectDigest(ctx, identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records.Attestations, 2, fmt.Sprintf("expected 2 records, got %d", len(records.Attestations)))

	// Then, fetch attestations by a single subject digest
	identifiers.SubjectDigests = nil
	identifiers.SubjectDigest = subjectDigests[0]
	records, err = tmaService.ListAttestationsBySubjectDigest(ctx, identifiers, &cursor)
	assert.NoError(t, err)
	assert.Len(t, records.Attestations, 1)
}

func TestReleaseAttestationConstraint(t *testing.T) {
	ctx := context.Background()
	tmaService, cleanUp := NewTMAWithLocalDockerStorage(t)
	defer cleanUp(t)

	ownerID, repoID := uint64(rand.Intn(9999)+1), uint64(rand.Intn(9999)+1)
	identifiers := attestation.IdentifiersGitHub{
		OwnerID:                  &ownerID,
		RepositoryID:             &repoID,
		DomainID:                 2,
		ExpectReleaseAttestation: true,
	}
	testBundle := data.SigstoreBundleGitHubRelease(t)

	record, err := tmaService.CreateAttestation(ctx, testBundle, identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)
	assert.Equal(t, identifiers.DomainID, record.DomainID)
	assert.Equal(t, identifiers.OwnerID, record.OwnerID)
	assert.Equal(t, identifiers.RepositoryID, record.RepositoryID)
	assert.Equal(t, TestReleasesTag, record.Tag)

	record, err = tmaService.CreateAttestation(ctx, testBundle, identifiers)
	assert.ErrorContains(t, err, "ConflictError: release attestation constraint failed")
	assert.Nil(t, record)
}
