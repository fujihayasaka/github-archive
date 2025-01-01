package service

import (
	"context"
	"testing"
	"time"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/github/trust-metadata-api/pkg/auth"
	"github.com/github/trust-metadata-api/pkg/storage"
	"github.com/github/trust-metadata-api/pkg/storage/mysql"
	"github.com/github/trust-metadata-api/testing/data"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

/*
	CreateNPMAttestation
*/

func TestService_CreateNPMAttestation(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundle(t)
	record, err := tma.CreateNPMAttestation(context.Background(), bundle, attestation.IdentifiersNPM{
		DomainID: 1,
		Purl:     TestPurl,
	})
	assert.NotZero(t, record)
	assert.NoError(t, err)
}

func TestService_CreateNPMAttestationDuplicate(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundle(t)
	record, err := tma.CreateNPMAttestation(context.Background(), bundle, attestation.IdentifiersNPM{
		DomainID: 1,
		Purl:     TestPurl,
	})
	assert.NotZero(t, record)
	assert.NoError(t, err)
	record, err = tma.CreateNPMAttestation(context.Background(), bundle, attestation.IdentifiersNPM{
		DomainID: 1,
		Purl:     TestPurl,
	})
	assert.Nil(t, record)
	assert.ErrorAs(t, err, &ConflictError{})
	assert.Contains(t, clientFacingError(err), "attestation for given (purl, predicateType) already exists")
	assert.Equal(t, err.Error(), "ConflictError: attestation for given (purl, predicateType) already exists")
}

func TestService_CreateNPMAttestation_StoreError(t *testing.T) {
	tma := NewTestTMAWithStore(t, &storage.FailInMemoryStore{})
	bundle := data.SigstoreBundle(t)
	record, err := tma.CreateNPMAttestation(context.Background(), bundle, attestation.IdentifiersNPM{
		DomainID: 1,
		Purl:     TestPurl,
	})
	assert.Nil(t, record)
	assert.Equal(t, "internal error", clientFacingError(err))
}

func TestService_CreateNPMAttestation_InvalidParams(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundle(t)
	bundle.MediaType = "invalid media type"
	attestationIdentifier, err := tma.CreateNPMAttestation(context.Background(), bundle, attestation.IdentifiersNPM{
		DomainID: 1,
		Purl:     TestPurl,
	})
	assert.Zero(t, attestationIdentifier)
	assert.ErrorAs(t, err, &BadRequestError{})
	assert.ErrorIs(t, err, sgbundle.ErrValidation)
	assert.Contains(t, clientFacingError(err), "validation error: unsupported media type")
	assert.Equal(t, err.Error(), "BadRequestError: error getting bundle version: validation error: unsupported media type: invalid media type")
}

func TestService_CreateNPMAttestation_VerifySignatureFail(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundle(t)
	bundle.Content.(*protobundle.Bundle_DsseEnvelope).DsseEnvelope.Signatures[0].Sig = []byte("invalid signature")
	attestationIdentifier, err := tma.CreateNPMAttestation(context.Background(), bundle, attestation.IdentifiersNPM{
		DomainID: 1,
		Purl:     TestPurl,
	})
	assert.Zero(t, attestationIdentifier)
	assert.ErrorAs(t, err, &BadRequestError{})
}

func TestService_CreateNPMAttestation_ParseSignatureEnvelopeFail(t *testing.T) {
	tma := NewTestTMA(t)
	bundle := data.SigstoreBundle(t)
	bundle.Content.(*protobundle.Bundle_DsseEnvelope).DsseEnvelope.Payload = []byte("invalid payload")
	attestationIdentifier, err := tma.CreateNPMAttestation(context.Background(), bundle, attestation.IdentifiersNPM{
		DomainID: 1,
		Purl:     TestPurl,
	})
	assert.Zero(t, attestationIdentifier)
	assert.ErrorAs(t, err, &BadRequestError{})
}

func TestService_CreateNPMAttestation_DigestsDontMatch(t *testing.T) {
	purl := TestPurl
	store := storage.NewInMemoryStore()
	bundle := data.SigstoreBundle(t)
	sgBundle, err := sgbundle.NewBundle(bundle)
	require.NoError(t, err)

	// store the bundle directly in the database with a different digest
	err = store.StoreNpmAttestation(context.Background(), &attestation.Record{
		Bundle:        bundle,
		Purl:          purl,
		SubjectDigest: "sha256:f00ba7",
		SubjectName:   SubjectName,
	}, sgBundle)
	require.NoError(t, err)

	tma := NewTestTMAWithStore(t, store)
	// this should fail because the digest in the bundle doesn't match the one in the database for the same purl
	record, err := tma.CreateNPMAttestation(context.Background(), bundle, attestation.IdentifiersNPM{
		Purl: purl,
	})
	assert.Nil(t, record)
	var conflict ConflictError
	assert.ErrorAs(t, err, &conflict)
	assert.Equal(t, clientFacingError(err), ErrDigestsMismatch.Error())
}

/*
  GetAttestations
*/

// TODO: Remove in favor of GetNPMAttestations tests
func TestService_GetAttestations(t *testing.T) {
	tma := NewTestTMA(t)

	// create new Attestation instance for test
	purl := TestPurl
	subjectDigest := SubjectDigest
	attestationRecord := attestation.Record{
		SubjectDigest: subjectDigest,
		SubjectName:   SubjectName,
		Purl:          purl,
	}
	bundle, err := sgbundle.NewBundle(data.SigstoreBundle(t))
	require.NoError(t, err)

	// store attestation
	err = tma.store.StoreNpmAttestation(context.Background(), &attestationRecord, bundle)
	require.NoError(t, err)

	serviceClient := auth.ServiceClient{
		ClientID: "npm/read",
		Domain:   "npm",
		DomainID: 1,
	}
	ctx := auth.WithCurrentClient(context.Background(), serviceClient)

	attestationIdentifier := attestation.IdentifiersNPM{
		Purl: purl,
	}
	attestationRecords, err := tma.GetNPMAttestations(ctx, attestationIdentifier)
	attestations := attestationRecords.Attestations

	assert.Len(t, attestations, 1)
	assert.Equal(t, purl, attestations[0].Purl)
	assert.Equal(t, subjectDigest, attestations[0].SubjectDigest)
	assert.Equal(t, SubjectName, attestations[0].SubjectName)
	assert.NoError(t, err)
}

func TestService_GetNPMAttestations(t *testing.T) {
	tma := NewTestTMA(t)

	// create new Attestation instance for test
	purl := TestPurl
	subjectDigest := SubjectDigest
	attestationRecord := attestation.Record{
		SubjectDigest: subjectDigest,
		SubjectName:   SubjectName,
		Purl:          purl,
		DomainID:      1,
	}
	bundle, err := sgbundle.NewBundle(data.SigstoreBundle(t))
	require.NoError(t, err)

	// store attestation
	err = tma.store.StoreNpmAttestation(context.Background(), &attestationRecord, bundle)
	require.NoError(t, err)

	serviceClient := auth.ServiceClient{
		ClientID: "npm/read",
		Domain:   "npm",
		DomainID: 1,
	}
	ctx := auth.WithCurrentClient(context.Background(), serviceClient)

	attestationIdentifier := attestation.IdentifiersNPM{
		Purl:     purl,
		DomainID: 1,
	}
	attestationRecords, err := tma.GetNPMAttestations(ctx, attestationIdentifier)
	attestations := attestationRecords.Attestations

	assert.Len(t, attestations, 1)
	assert.Equal(t, purl, attestations[0].Purl)
	assert.Equal(t, subjectDigest, attestations[0].SubjectDigest)
	assert.Equal(t, SubjectName, attestations[0].SubjectName)
	assert.NoError(t, err)
}

/*
  GetProvenanceAttestationSummary
*/

func TestService_GetProvenanceAttestationSummaryWithSLSA02(t *testing.T) {
	tma := NewTestTMA(t)

	bundle, err := sgbundle.NewBundle(data.SigstoreJs100ProtoBundle(t))
	assert.NoError(t, err)

	// create new Attestation instance for test
	attestationRecord := attestation.Record{
		Purl:          TestPurl,
		PredicateType: "https://slsa.dev/provenance/v0.2",
	}

	// store attestation
	err = tma.store.StoreNpmAttestation(context.Background(), &attestationRecord, bundle)
	assert.NoError(t, err)

	attestationIdentifier := attestation.IdentifiersNPM{
		Purl: TestPurl,
	}

	provenanceSummary, err := tma.GetProvenanceAttestationSummary(context.Background(), attestationIdentifier)
	expectedProvenanceSummary := attestation.ProvenanceSummary{
		SubjectAlternativeName:            "https://github.com/sigstore/sigstore-js/.github/workflows/publish.yml@refs/tags/v1.0.0",
		Issuer:                            "https://token.actions.githubusercontent.com",
		IssuerDisplayName:                 "GitHub Actions",
		BuildTrigger:                      "release",
		BuildConfigURI:                    "https://github.com/sigstore/sigstore-js/.github/workflows/publish.yml@refs/tags/v1.0.0",
		SourceRepositoryURI:               "https://github.com/sigstore/sigstore-js",
		SourceRepositoryDigest:            "06528997c3c8ab9f864fad9a3658446aca7fd86d",
		SourceRepositoryRef:               "refs/tags/v1.0.0",
		RunInvocationURI:                  "https://github.com/sigstore/sigstore-js/actions/runs/4137028816/attempts/1",
		ExpiresAt:                         time.Date(2023, time.February, 9, 18, 6, 0, 0, time.UTC),
		IncludedAt:                        time.Date(2023, time.February, 9, 17, 56, 0, 0, time.UTC),
		ResolvedSourceRepositoryCommitURI: "https://github.com/sigstore/sigstore-js/tree/06528997c3c8ab9f864fad9a3658446aca7fd86d",
		TransparencyLogURI:                "https://search.sigstore.dev/?logIndex=12988397",
		CertificateIssuer:                 "CN=sigstore-intermediate,O=sigstore.dev",
		BuildConfigDisplayName:            ".github/workflows/publish.yml",
		ResolvedBuildConfigURI:            "https://github.com/sigstore/sigstore-js/actions/runs/4137028816/workflow",
		ArtifactName:                      "pkg:npm/sigstore@1.0.0",
	}

	assert.Equal(t, &expectedProvenanceSummary, provenanceSummary, "provenance summary mismatch")
	assert.NoError(t, err)
}

func TestService_GetProvenanceAttestationSummaryWithBothSLSA1AndSLSA02(t *testing.T) {
	tma := NewTestTMA(t)

	// create new Attestation instance for test
	bundle, err := sgbundle.NewBundle(data.SigstoreJs100ProtoBundle(t))
	require.NoError(t, err)

	purl := TestPurl
	slsaV02AttestationRecord := attestation.Record{
		Purl:          purl,
		PredicateType: "https://slsa.dev/provenance/v0.2",
	}

	// store attestation
	err = tma.store.StoreNpmAttestation(context.Background(), &slsaV02AttestationRecord, bundle)
	require.NoError(t, err)

	slsa1ProvenanceBundle, err := sgbundle.NewBundle(data.SigstoreBundleSLSA1Provenance(t))
	require.NoError(t, err)

	slsaV1AttestationRecord := attestation.Record{
		Purl:          purl,
		PredicateType: "https://slsa.dev/provenance/v1",
	}

	// store attestation
	err = tma.store.StoreNpmAttestation(context.Background(), &slsaV1AttestationRecord, slsa1ProvenanceBundle)
	require.NoError(t, err)

	attestationIdentifier := attestation.IdentifiersNPM{
		Purl: purl,
	}

	provenanceSummary, err := tma.GetProvenanceAttestationSummary(context.Background(), attestationIdentifier)
	expectedProvenanceSummary := attestation.ProvenanceSummary{
		SubjectAlternativeName:            "https://github.com/github/package-security-learning-labs/.github/workflows/npm-publish-with-provenance.yml@refs/heads/main",
		CertificateIssuer:                 "CN=sigstore-intermediate,O=sigstore.dev",
		Issuer:                            "https://token.actions.githubusercontent.com",
		IssuerDisplayName:                 "GitHub Actions",
		BuildTrigger:                      "workflow_dispatch",
		BuildConfigURI:                    "https://github.com/github/package-security-learning-labs/.github/workflows/npm-publish-with-provenance.yml@refs/heads/main",
		SourceRepositoryURI:               "https://github.com/github/package-security-learning-labs",
		SourceRepositoryDigest:            "4e36c269fbe0e6fd97bce24b084b892d526dc4d2",
		SourceRepositoryRef:               "refs/heads/main",
		RunInvocationURI:                  "https://github.com/github/package-security-learning-labs/actions/runs/5389832127/attempts/1",
		ExpiresAt:                         time.Date(2023, time.June, 27, 12, 44, 16, 0, time.UTC),
		IncludedAt:                        time.Date(2023, time.June, 27, 12, 34, 17, 0, time.UTC),
		ResolvedSourceRepositoryCommitURI: "https://github.com/github/package-security-learning-labs/tree/4e36c269fbe0e6fd97bce24b084b892d526dc4d2",
		TransparencyLogURI:                "https://search.sigstore.dev/?logIndex=25278380",
		BuildConfigDisplayName:            ".github/workflows/npm-publish-with-provenance.yml",
		ResolvedBuildConfigURI:            "https://github.com/github/package-security-learning-labs/actions/runs/5389832127/workflow",
		ArtifactName:                      "pkg:npm/%40ps-testing/dummy-provenance@1.0.0-5389832127.1",
	}

	assert.Equal(t, &expectedProvenanceSummary, provenanceSummary, "provenance summary mismatch")
	assert.NoError(t, err)
}

func TestService_GetProvenanceAttestationSummaryWithBothSLSA1AndSLSA02WithReverseOrder(t *testing.T) {
	tma := NewTestTMA(t)

	// create new Attestation instance for test
	bundle, err := sgbundle.NewBundle(data.SigstoreBundleSLSA1Provenance(t))
	require.NoError(t, err)

	purl := TestPurl
	slsaV1AttestationRecord := attestation.Record{
		Purl:          purl,
		PredicateType: "https://slsa.dev/provenance/v1",
	}

	// store attestation
	err = tma.store.StoreNpmAttestation(context.Background(), &slsaV1AttestationRecord, bundle)
	require.NoError(t, err)

	slsaV02Bundle, err := sgbundle.NewBundle(data.SigstoreJs100ProtoBundle(t))
	require.NoError(t, err)

	slsaV02AttestationRecord := attestation.Record{
		Purl:          purl,
		PredicateType: "https://slsa.dev/provenance/v0.2",
	}

	// store attestation
	err = tma.store.StoreNpmAttestation(context.Background(), &slsaV02AttestationRecord, slsaV02Bundle)
	require.NoError(t, err)

	attestationIdentifier := attestation.IdentifiersNPM{
		Purl: purl,
	}

	provenanceSummary, err := tma.GetProvenanceAttestationSummary(context.Background(), attestationIdentifier)
	expectedProvenanceSummary := attestation.ProvenanceSummary{
		SubjectAlternativeName:            "https://github.com/github/package-security-learning-labs/.github/workflows/npm-publish-with-provenance.yml@refs/heads/main",
		CertificateIssuer:                 "CN=sigstore-intermediate,O=sigstore.dev",
		Issuer:                            "https://token.actions.githubusercontent.com",
		IssuerDisplayName:                 "GitHub Actions",
		BuildTrigger:                      "workflow_dispatch",
		BuildConfigURI:                    "https://github.com/github/package-security-learning-labs/.github/workflows/npm-publish-with-provenance.yml@refs/heads/main",
		SourceRepositoryURI:               "https://github.com/github/package-security-learning-labs",
		SourceRepositoryDigest:            "4e36c269fbe0e6fd97bce24b084b892d526dc4d2",
		SourceRepositoryRef:               "refs/heads/main",
		RunInvocationURI:                  "https://github.com/github/package-security-learning-labs/actions/runs/5389832127/attempts/1",
		ExpiresAt:                         time.Date(2023, time.June, 27, 12, 44, 16, 0, time.UTC),
		IncludedAt:                        time.Date(2023, time.June, 27, 12, 34, 17, 0, time.UTC),
		ResolvedSourceRepositoryCommitURI: "https://github.com/github/package-security-learning-labs/tree/4e36c269fbe0e6fd97bce24b084b892d526dc4d2",
		TransparencyLogURI:                "https://search.sigstore.dev/?logIndex=25278380",
		BuildConfigDisplayName:            ".github/workflows/npm-publish-with-provenance.yml",
		ResolvedBuildConfigURI:            "https://github.com/github/package-security-learning-labs/actions/runs/5389832127/workflow",
		ArtifactName:                      "pkg:npm/%40ps-testing/dummy-provenance@1.0.0-5389832127.1",
	}

	assert.Equal(t, &expectedProvenanceSummary, provenanceSummary, "provenance summary mismatch")
	assert.NoError(t, err)
}

func TestService_GetProvenanceAttestationSummaryWithSLSA1(t *testing.T) {
	tma := NewTestTMA(t)
	// create new Attestation instance for test
	bundle, err := sgbundle.NewBundle(data.SigstoreBundleSLSA1Provenance(t))
	require.NoError(t, err)

	purl := TestPurl
	attestationRecord := attestation.Record{
		Purl:          purl,
		PredicateType: "https://slsa.dev/provenance/v1",
	}

	// store attestation
	err = tma.store.StoreNpmAttestation(context.Background(), &attestationRecord, bundle)
	require.NoError(t, err)

	attestationIdentifier := attestation.IdentifiersNPM{
		Purl: purl,
	}

	provenanceSummary, err := tma.GetProvenanceAttestationSummary(context.Background(), attestationIdentifier)
	expectedProvenanceSummary := attestation.ProvenanceSummary{
		SubjectAlternativeName:            "https://github.com/github/package-security-learning-labs/.github/workflows/npm-publish-with-provenance.yml@refs/heads/main",
		CertificateIssuer:                 "CN=sigstore-intermediate,O=sigstore.dev",
		Issuer:                            "https://token.actions.githubusercontent.com",
		IssuerDisplayName:                 "GitHub Actions",
		BuildTrigger:                      "workflow_dispatch",
		BuildConfigURI:                    "https://github.com/github/package-security-learning-labs/.github/workflows/npm-publish-with-provenance.yml@refs/heads/main",
		SourceRepositoryURI:               "https://github.com/github/package-security-learning-labs",
		SourceRepositoryDigest:            "4e36c269fbe0e6fd97bce24b084b892d526dc4d2",
		SourceRepositoryRef:               "refs/heads/main",
		RunInvocationURI:                  "https://github.com/github/package-security-learning-labs/actions/runs/5389832127/attempts/1",
		ExpiresAt:                         time.Date(2023, time.June, 27, 12, 44, 16, 0, time.UTC),
		IncludedAt:                        time.Date(2023, time.June, 27, 12, 34, 17, 0, time.UTC),
		ResolvedSourceRepositoryCommitURI: "https://github.com/github/package-security-learning-labs/tree/4e36c269fbe0e6fd97bce24b084b892d526dc4d2",
		TransparencyLogURI:                "https://search.sigstore.dev/?logIndex=25278380",
		BuildConfigDisplayName:            ".github/workflows/npm-publish-with-provenance.yml",
		ResolvedBuildConfigURI:            "https://github.com/github/package-security-learning-labs/actions/runs/5389832127/workflow",
		ArtifactName:                      "pkg:npm/%40ps-testing/dummy-provenance@1.0.0-5389832127.1",
	}

	assert.Equal(t, &expectedProvenanceSummary, provenanceSummary, "provenance summary mismatch")
	assert.NoError(t, err)
}

func TestService_GetAttestationsByPurlFails(t *testing.T) {
	failStore := &storage.FailInMemoryStore{}
	tma := NewTestTMAWithStore(t, failStore)

	serviceClient := auth.ServiceClient{
		ClientID: "npm/read",
		Domain:   "npm",
		DomainID: 1,
	}
	ctx := auth.WithCurrentClient(context.Background(), serviceClient)

	attestationIdentifier := attestation.IdentifiersNPM{
		Purl: TestPurl,
	}

	attestationRecords, err := tma.GetNPMAttestations(ctx, attestationIdentifier)

	assert.Nil(t, attestationRecords)
	assert.ErrorIs(t, err, mysql.ErrAttestationNotFound)
}

// Test that TMAService#GetAttestationsByPurl is called when the provide ServiceClient.DomainID
// does not represent github
func TestCallToGetAttestationsByPurl(t *testing.T) {
	serviceClient := auth.ServiceClient{
		ClientID: "npm/read",
		Domain:   "npm",
		DomainID: 1,
	}
	ctx := auth.WithCurrentClient(context.Background(), serviceClient)
	attestationIdentifier := attestation.IdentifiersNPM{
		Purl: TestPurl,
	}

	mockDB := newMockDatabaseEndpoints()
	mockDB.Replica.(*MockDB).On("GetAttestationsByPurl").Return([]attestation.Record{
		{SubjectDigest: "sha512:bbfd372fc9beeb777fe35d05bb10c0c70a9733d366a75fed7dd18866c7391de3ee7e88ba74dd47abf3e15c845e547fcf0e5c3da80854c751554224d3a6d4e55f"},
	}, nil)

	tma := NewTestTMAWithDB(t, mockDB)
	_, err := tma.GetNPMAttestations(ctx, attestationIdentifier)
	assert.NoError(t, err)
	mockDB.Replica.(*MockDB).AssertCalled(t, "GetAttestationsByPurl")
}
