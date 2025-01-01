//go:build integration

package service

import (
	"context"
	"testing"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/testing/data"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
)

const (
	svcTestNPMDomainID = 1
	svcTestPurl        = "pkg:npm/sigstore@2.2.0" // From data.SigstoreJs300ProtoBundle
)

// TestCreateNPMAttestation creating an NPM attestation record with service.CreateNPMAttestation.
func TestCreateNPMAttestation(t *testing.T) {
	// Setup
	tmaService, cleanUp := NewTMAWithLocalDockerStorage(t)
	defer cleanUp(t)

	identifiers := attestation.IdentifiersNPM{
		DomainID: svcTestNPMDomainID,
		Purl:     svcTestPurl,
	}
	testBundle := data.SigstoreJs300ProtoBundle(t)

	// Create the NPM attestation record and verify the record was created
	record, err := tmaService.CreateNPMAttestation(context.Background(), testBundle, identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)
	assert.Equal(t, identifiers.Purl, record.Purl)
	assert.Equal(t, identifiers.DomainID, record.DomainID)
}

func TestCreateNPMAttestation_DigestsDontMatch(t *testing.T) {
	// Setup
	ctx := context.Background()
	tmaService, cleanUp := NewTMAWithLocalDockerStorage(t)
	defer cleanUp(t)

	identifiers := attestation.IdentifiersNPM{
		DomainID: svcTestNPMDomainID,
		Purl:     svcTestPurl,
	}
	testBundle := data.SigstoreJs300ProtoBundle(t)

	// Create the NPM attestation record and verify the record was created
	record, err := tmaService.CreateNPMAttestation(ctx, testBundle, identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)
	assert.Equal(t, identifiers.Purl, record.Purl)

	// Attempt to create a second attestation with the same purl but a different subject digest
	secondBundle := data.SigstoreBundle(t)
	secondRecord, err := tmaService.CreateNPMAttestation(ctx, secondBundle, identifiers)
	assert.Error(t, err)
	assert.Nil(t, secondRecord)

	sgSecondBundle, err := sgbundle.NewBundle(secondBundle)
	assert.NoError(t, err)

	res, err := tmaService.VerifyBundle(ctx, sgSecondBundle)
	assert.NoError(t, err)

	subjects, err := attestation.ValidateStatement(res.Statement)
	assert.NoError(t, err)

	digestIsUnique, err := tmaService.ValidatePurlSubjectDigestUniqueness(ctx, identifiers, subjects[0].SubjectDigest.String())
	assert.NoError(t, err)
	assert.False(t, digestIsUnique)
}

// TestGetNPMAttestations tests the full round trip for service.GetNPMAttestations.
func TestGetNPMAttestations(t *testing.T) {
	// Setup
	ctx := context.Background()
	tmaService, cleanUp := NewTMAWithLocalDockerStorage(t)
	defer cleanUp(t)

	identifiers := attestation.IdentifiersNPM{
		DomainID: svcTestNPMDomainID,
		Purl:     svcTestPurl,
	}
	testBundle := data.SigstoreJs300ProtoBundle(t)

	// Create the NPM attestation record
	record, err := tmaService.CreateNPMAttestation(ctx, testBundle, identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)
	assert.Equal(t, svcTestPurl, record.Purl)
	assert.Nil(t, record.Bundle)

	// Get the NPM attestation record from the service layer
	attestationRecords, err := tmaService.GetNPMAttestations(ctx, identifiers)
	assert.NoError(t, err)
	assert.Len(t, attestationRecords.Attestations, 1)
	assert.Equal(t, identifiers.DomainID, attestationRecords.Attestations[0].DomainID)
	assert.Equal(t, identifiers.Purl, attestationRecords.Attestations[0].Purl)
	assert.Equal(t, testBundle.String(), attestationRecords.Attestations[0].Bundle.String())
}

// TestGetProvenanceAttestationSummary tests the full round trip for service.GetProvenanceAttestationSummary.
func TestGetProvenanceAttestationSummary(t *testing.T) {
	/*
		This tests the full round trip in the Service layer by storing an NPM attestation in the
		database with service.CreateNPMAttestation then retrieving it with service.GetProvenanceAttestationSummary.
	*/
	// Setup
	ctx := context.Background()
	tmaService, cleanUp := NewTMAWithLocalDockerStorage(t)
	defer cleanUp(t)

	identifiers := attestation.IdentifiersNPM{
		DomainID: svcTestNPMDomainID,
		Purl:     svcTestPurl,
	}
	testBundle := data.SigstoreJs300ProtoBundle(t)

	// Create the NPM attestation record
	record, err := tmaService.CreateNPMAttestation(ctx, testBundle, identifiers)
	assert.NoError(t, err)
	assert.NotNil(t, record)

	// Get the NPM attestation provenance summary
	attestation, err := tmaService.GetProvenanceAttestationSummary(ctx, identifiers)
	assert.Nil(t, err)
	assert.Equal(t, svcTestPurl, attestation.ArtifactName)
	assert.Equal(t, "https://github.com/sigstore/sigstore-js", attestation.SourceRepositoryURI)
	assert.Equal(t, "d9093d4b3b99d9ee446633ac7074e43cea78c727", attestation.SourceRepositoryDigest)
	assert.Equal(t, "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main", attestation.BuildConfigURI)
	// These are all used on the npmjs.com Provenance section. Example: https://www.npmjs.com/package/sigstore
	assert.Equal(t, "GitHub Actions", attestation.IssuerDisplayName)
	assert.Equal(t, "https://github.com/sigstore/sigstore-js/actions/runs/7507343033/attempts/1", attestation.RunInvocationURI)
	assert.Equal(t, "https://github.com/sigstore/sigstore-js/tree/d9093d4b3b99d9ee446633ac7074e43cea78c727", attestation.ResolvedSourceRepositoryCommitURI)
	assert.Equal(t, "https://github.com/sigstore/sigstore-js/actions/runs/7507343033/workflow", attestation.ResolvedBuildConfigURI)
	assert.Equal(t, ".github/workflows/release.yml", attestation.BuildConfigDisplayName)
	assert.Equal(t, "https://search.sigstore.dev/?logIndex=63284502", attestation.TransparencyLogURI)
}
