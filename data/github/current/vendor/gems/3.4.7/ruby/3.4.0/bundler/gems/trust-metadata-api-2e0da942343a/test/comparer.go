package test

import (
	"testing"

	"github.com/stretchr/testify/assert"

	rpc "github.com/github/trust-metadata-api/pkg/rpc/v0"
)

// Compare ProvenanceSummary
func CompareProvenanceSummary(t *testing.T, actual, expected *rpc.ProvenanceSummary) {
	// Compare SubjectAlternativeName
	assert.Equal(t, expected.SubjectAlternativeName, actual.SubjectAlternativeName, "SubjectAlternativeName mismatch")

	// Compare CertificateIssuer
	assert.Equal(t, expected.CertificateIssuer, actual.CertificateIssuer, "CertificateIssuer mismatch")

	// Compare Issuer
	assert.Equal(t, expected.Issuer, actual.Issuer, "Issuer mismatch")

	// Compare IssuerDisplayName
	assert.Equal(t, expected.IssuerDisplayName, actual.IssuerDisplayName, "IssuerDisplayName mismatch")

	// Compare BuildTrigger
	assert.Equal(t, expected.BuildTrigger, actual.BuildTrigger, "BuildTrigger mismatch")

	// Compare BuildConfigUri
	assert.Equal(t, expected.BuildConfigUri, actual.BuildConfigUri, "BuildConfigUri mismatch")

	// Compare SourceRepositoryUri
	assert.Equal(t, expected.SourceRepositoryUri, actual.SourceRepositoryUri, "SourceRepositoryUri mismatch")

	// Compare SourceRepositoryDigest
	assert.Equal(t, expected.SourceRepositoryDigest, actual.SourceRepositoryDigest, "SourceRepositoryDigest mismatch")

	// Compare SourceRepositoryRef
	assert.Equal(t, expected.SourceRepositoryRef, actual.SourceRepositoryRef, "SourceRepositoryRef mismatch")

	// Compare RunInvocationUri
	assert.Equal(t, expected.RunInvocationUri, actual.RunInvocationUri, "RunInvocationUri mismatch")

	// Compare ExpiresAt
	assert.Equal(t, expected.ExpiresAt.AsTime(), actual.ExpiresAt.AsTime(), "ExpiresAt mismatch")

	// Compare IncludedAt
	assert.Equal(t, expected.IncludedAt.AsTime(), actual.IncludedAt.AsTime(), "IncludedAt mismatch")

	// Compare ResolvedSourceRepositoryCommitUri
	assert.Equal(t, expected.ResolvedSourceRepositoryCommitUri, actual.ResolvedSourceRepositoryCommitUri, "ResolvedSourceRepositoryCommitUri mismatch")

	// Compare TransparencyLogUri
	assert.Equal(t, expected.TransparencyLogUri, actual.TransparencyLogUri, "TransparencyLogUri mismatch")

	// Compare BuildConfigDisplayName
	assert.Equal(t, expected.BuildConfigDisplayName, actual.BuildConfigDisplayName, "BuildConfigDisplayName mismatch")

	// Compare ResolvedBuildConfigURI
	assert.Equal(t, expected.ResolvedBuildConfigUri, actual.ResolvedBuildConfigUri, "ResolvedBuildConfigUri mismatch")
}
