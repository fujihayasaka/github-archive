package attestation

import (
	"context"
	"testing"
	"time"

	"github.com/github/trust-metadata-api/test/data"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/stretchr/testify/assert"
)

func TestNewFulcioCertificateSummary_Pre12(t *testing.T) {
	bundle := testProtobufBundle(t, data.SigstoreJs100ProtoBundle(t))

	cert, err := leafCertificate(bundle)
	if err != nil {
		t.Fatalf("failed to get leaf cert: %v", err)
	}

	fcs, err := NewFulcioCertificateSummary(cert)
	if err != nil {
		t.Fatalf("failed to get cert summary: %v", err)
	}

	assert.False(t, fcs.IsPostFulcioV1_2)

	expectedFcs := FulcioCertificateSummary{
		SubjectAlternativeNameURL: "https://github.com/sigstore/sigstore-js/.github/workflows/publish.yml@refs/tags/v1.0.0",
		Issuer:                    "https://token.actions.githubusercontent.com",
		BuildTrigger:              "release",
		BuildConfigURI:            "",                                        // NOTE HOW THIS IS EMPTY
		SourceRepositoryURI:       "https://github.com/sigstore/sigstore-js", // NOTE HOW THIS IS THE FULL URL
		SourceRepositoryDigest:    "06528997c3c8ab9f864fad9a3658446aca7fd86d",
		SourceRepositoryRef:       "refs/tags/v1.0.0",
		RunInvocationURI:          "", // NOTE HOW THIS IS EMPTY
		NotAfter:                  time.Date(2023, time.February, 9, 18, 6, 0, 0, time.UTC),
		CertificateIssuer:         "CN=sigstore-intermediate,O=sigstore.dev",
	}

	assert.Equal(t, expectedFcs, fcs, "summary mismatch")
}

func TestProvenanceSummary_Pre12(t *testing.T) {
	bundle := testProtobufBundle(t, data.SigstoreJs100ProtoBundle(t))

	ctx := context.Background()
	summary, err := NewProvenanceSummary(ctx, bundle)
	if err != nil {
		t.Fatalf("failed to get summary: %v", err)
	}

	// contrast with the FulcioCertificateSummary in `TestNewFulcioCertificateSummary_Pre12`:
	// we expect to fill in the BuildConfigURI and the RunInvocationURI
	expectedSummary := ProvenanceSummary{
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
		BuildConfigDisplayName:            ".github/workflows/publish.yml",
		ResolvedBuildConfigURI:            "https://github.com/sigstore/sigstore-js/actions/runs/4137028816/workflow",
		TransparencyLogURI:                "https://search.sigstore.dev/?logIndex=12988397",
		CertificateIssuer:                 "CN=sigstore-intermediate,O=sigstore.dev",
		ArtifactName:                      "pkg:npm/sigstore@1.0.0",
	}

	assert.Equal(t, expectedSummary, summary, "provenance summary mismatch")
}

// Some bundle predicates don't even include a GITHUB_WORKFLOW_REF, so we need to handle that case
func TestProvenanceSummary_WonkyPre12(t *testing.T) {
	bundle := testProtobufBundle(t, data.SigstoreJs030ProtoBundle(t))

	ctx := context.Background()
	summary, err := NewProvenanceSummary(ctx, bundle)
	if err != nil {
		t.Fatalf("failed to get summary: %v", err)
	}

	// contrast with the FulcioCertificateSummary in `TestNewFulcioCertificateSummary_Pre12`:
	// we expect to fill in the BuildConfigURI and the RunInvocationURI
	expectedSummary := ProvenanceSummary{
		SubjectAlternativeName:            "https://github.com/sigstore/sigstore-js/.github/workflows/publish.yml@refs/tags/v0.3.0",
		Issuer:                            "https://token.actions.githubusercontent.com",
		IssuerDisplayName:                 "GitHub Actions",
		BuildTrigger:                      "release",
		BuildConfigURI:                    "https://github.com/sigstore/sigstore-js/.github/workflows/publish.yml@refs/tags/v0.3.0", // NOTE how this is identical to the SAN
		SourceRepositoryURI:               "https://github.com/sigstore/sigstore-js",
		SourceRepositoryDigest:            "867975ea12e93be03a0db6d9290dbdc8545f52f2",
		SourceRepositoryRef:               "refs/tags/v0.3.0",
		RunInvocationURI:                  "https://github.com/sigstore/sigstore-js/actions/runs/3849718817/attempts/1",
		ExpiresAt:                         time.Date(2023, time.January, 5, 19, 33, 20, 0, time.UTC),
		IncludedAt:                        time.Date(2023, time.January, 5, 19, 23, 21, 0, time.UTC),
		ResolvedSourceRepositoryCommitURI: "https://github.com/sigstore/sigstore-js/tree/867975ea12e93be03a0db6d9290dbdc8545f52f2",
		BuildConfigDisplayName:            ".github/workflows/publish.yml",
		ResolvedBuildConfigURI:            "https://github.com/sigstore/sigstore-js/actions/runs/3849718817/workflow",
		TransparencyLogURI:                "https://search.sigstore.dev/?logIndex=10547270",
		CertificateIssuer:                 "CN=sigstore-intermediate,O=sigstore.dev",
		ArtifactName:                      "pkg:npm/sigstore@0.3.0",
	}

	assert.Equal(t, expectedSummary, summary, "provenance summary mismatch")
}

func TestNewFulcioCertificateSummary_Post12(t *testing.T) {
	bundle := testProtobufBundle(t, data.SigstoreJs140ProtoBundle(t))

	cert, err := leafCertificate(bundle)
	if err != nil {
		t.Fatalf("failed to get leaf cert: %v", err)
	}

	fcs, err := NewFulcioCertificateSummary(cert)
	if err != nil {
		t.Fatalf("failed to get cert summary: %v", err)
	}

	assert.True(t, fcs.IsPostFulcioV1_2)

	// of note:
	// - the BuildConfigURI is set to the full GitHub URL
	// - the RunInvocationURI is set to the full GitHub URL
	// - the SourceRepositoryURI is set to the full GitHub URL
	// and all of these come straight from the cert.
	expectedFcs := FulcioCertificateSummary{
		IsPostFulcioV1_2:          true,
		SubjectAlternativeNameURL: "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main",
		Issuer:                    "https://token.actions.githubusercontent.com",
		BuildTrigger:              "push",
		BuildConfigURI:            "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main",
		SourceRepositoryURI:       "https://github.com/sigstore/sigstore-js",
		SourceRepositoryDigest:    "b4e96a2df70abbcb0cc210f50568de04d46c23e8",
		SourceRepositoryRef:       "refs/heads/main",
		RunInvocationURI:          "https://github.com/sigstore/sigstore-js/actions/runs/4788144884/attempts/1",
		NotAfter:                  time.Date(2023, time.April, 24, 15, 36, 22, 0, time.UTC),
		CertificateIssuer:         "CN=sigstore-intermediate,O=sigstore.dev",
	}

	assert.Equal(t, expectedFcs, fcs, "summary mismatch")
}

func TestProvenanceSummary_Post12(t *testing.T) {
	bundle := testProtobufBundle(t, data.SigstoreJs140ProtoBundle(t))

	ctx := context.Background()
	summary, err := NewProvenanceSummary(ctx, bundle)
	if err != nil {
		t.Fatalf("failed to get summary: %v", err)
	}

	// In addition to the fields extracted from the certificate in FulcioCertificateSummary
	// we construct the following fields:
	// - ResolvedSourceRepositoryCommitURI
	// - BuildConfigDisplayName
	// - ResolvedBuildConfigURI
	// - TransparencyLogURI
	expectedSummary := ProvenanceSummary{
		SubjectAlternativeName:            "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main",
		Issuer:                            "https://token.actions.githubusercontent.com",
		IssuerDisplayName:                 "GitHub Actions",
		BuildTrigger:                      "push",
		BuildConfigURI:                    "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main",
		SourceRepositoryURI:               "https://github.com/sigstore/sigstore-js",
		SourceRepositoryDigest:            "b4e96a2df70abbcb0cc210f50568de04d46c23e8",
		SourceRepositoryRef:               "refs/heads/main",
		RunInvocationURI:                  "https://github.com/sigstore/sigstore-js/actions/runs/4788144884/attempts/1",
		ExpiresAt:                         time.Date(2023, time.April, 24, 15, 36, 22, 0, time.UTC),
		IncludedAt:                        time.Date(2023, time.April, 24, 15, 26, 23, 0, time.UTC),
		ResolvedSourceRepositoryCommitURI: "https://github.com/sigstore/sigstore-js/tree/b4e96a2df70abbcb0cc210f50568de04d46c23e8",
		BuildConfigDisplayName:            ".github/workflows/release.yml",
		ResolvedBuildConfigURI:            "https://github.com/sigstore/sigstore-js/actions/runs/4788144884/workflow",
		TransparencyLogURI:                "https://search.sigstore.dev/?logIndex=18817304",
		CertificateIssuer:                 "CN=sigstore-intermediate,O=sigstore.dev",
		ArtifactName:                      "pkg:npm/sigstore@1.4.0",
	}

	assert.Equal(t, expectedSummary, summary, "provenance summary mismatch")
}

func TestNewFulcioCertificateSummary_GitLab(t *testing.T) {
	bundle := testProtobufBundle(t, data.GitLabAlpha01ProtoBundle(t))

	cert, err := leafCertificate(bundle)
	if err != nil {
		t.Fatalf("failed to get leaf cert: %v", err)
	}

	fcs, err := NewFulcioCertificateSummary(cert)
	if err != nil {
		t.Fatalf("failed to get cert summary: %v", err)
	}

	assert.True(t, fcs.IsPostFulcioV1_2)

	// Note:
	// - the BuildConfigURI *will* be set to a full GitLab URL pointing to the build config
	// - the RunInvocationURI is set to the full GitLab URL
	// - the SourceRepositoryURI is set to the full GitLab URL
	// and all of these come straight from the cert.
	expectedFcs := FulcioCertificateSummary{
		IsPostFulcioV1_2:          true,
		SubjectAlternativeNameURL: "https://gitlab.com/wlynch/npm-provenance-example@refs/heads/main",
		Issuer:                    "https://gitlab.com",
		BuildTrigger:              "web",
		// NOTE: This is currently set to job path but this is incorrect
		// and was removed in an upcoming Fulcio release until the
		// correct value can be set from the pipeline_ref claim
		BuildConfigURI:         "https://gitlab.com/wlynch/npm-provenance-example/-/jobs/4276586778",
		SourceRepositoryURI:    "https://gitlab.com/wlynch/npm-provenance-example",
		SourceRepositoryDigest: "891e58e84b85b94dcec8618d1ee51f3564022c85",
		SourceRepositoryRef:    "refs/heads/main",
		// NOTE: This is currently set to the pipeline path but this is incorrect and will be set to the job logs path
		RunInvocationURI:  "https://gitlab.com/wlynch/npm-provenance-example/-/pipelines/865814619",
		NotAfter:          time.Date(2023, time.May, 12, 15, 13, 20, 0, time.UTC),
		CertificateIssuer: "CN=sigstore-intermediate,O=sigstore.dev",
	}

	assert.Equal(t, expectedFcs, fcs, "summary mismatch")
}

func TestFulcioCertificateSummary_GitLabUpdatedBuilderSigner(t *testing.T) {
	bundle := testProtobufBundle(t, data.GitLabUpdatedBuildConfigRunInvocationProtoBundle(t))

	cert, err := leafCertificate(bundle)
	if err != nil {
		t.Fatalf("failed to get leaf cert: %v", err)
	}

	fcs, err := NewFulcioCertificateSummary(cert)
	if err != nil {
		t.Fatalf("failed to get cert summary: %v", err)
	}

	assert.True(t, fcs.IsPostFulcioV1_2)

	// Note:
	// - the BuildConfigURI has been updated to point to the build config
	// - the RunInvocationURI has been updated to point to the full GitLab URL for the job instead of pipeline run
	// - the SourceRepositoryURI is set to the full GitLab URL
	// and all of these come straight from the cert.
	expectedFcs := FulcioCertificateSummary{
		IsPostFulcioV1_2:          true,
		SubjectAlternativeNameURL: "https://gitlab.com/feelepxyz/gitlab-npm-provenance//.gitlab-ci.yml@refs/heads/main",
		Issuer:                    "https://gitlab.com",
		BuildTrigger:              "push",
		BuildConfigURI:            "https://gitlab.com/feelepxyz/gitlab-npm-provenance//.gitlab-ci.yml@refs/heads/main",
		SourceRepositoryURI:       "https://gitlab.com/feelepxyz/gitlab-npm-provenance",
		SourceRepositoryDigest:    "08f53be3997c251288d6cb2181abd3ac12a94da7",
		SourceRepositoryRef:       "refs/heads/main",
		RunInvocationURI:          "https://gitlab.com/feelepxyz/gitlab-npm-provenance/-/jobs/4734734047",
		NotAfter:                  time.Date(2023, time.July, 25, 9, 32, 10, 0, time.UTC),
		CertificateIssuer:         "CN=sigstore-intermediate,O=sigstore.dev",
	}

	assert.Equal(t, expectedFcs, fcs, "summary mismatch")
}

func TestProvenanceSummary_SLSA1(t *testing.T) {
	bundle := testProtobufBundle(t, data.SigstoreBundleSLSA1Provenance(t))

	ctx := context.Background()
	summary, err := NewProvenanceSummary(ctx, bundle)
	if err != nil {
		t.Fatalf("failed to get summary: %v", err)
	}

	expectedSummary := ProvenanceSummary{
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

	assert.Equal(t, expectedSummary, summary, "provenance summary mismatch")
}

func TestNewFulcioCertificateSummaryy_SLSA1(t *testing.T) {
	bundle := testProtobufBundle(t, data.SigstoreBundleSLSA1Provenance(t))

	cert, err := leafCertificate(bundle)
	if err != nil {
		t.Fatalf("failed to get leaf cert: %v", err)
	}

	fcs, err := NewFulcioCertificateSummary(cert)
	if err != nil {
		t.Fatalf("failed to get cert summary: %v", err)
	}

	assert.True(t, fcs.IsPostFulcioV1_2)

	expectedFcs := FulcioCertificateSummary{
		IsPostFulcioV1_2:          true,
		SubjectAlternativeNameURL: "https://github.com/github/package-security-learning-labs/.github/workflows/npm-publish-with-provenance.yml@refs/heads/main",
		CertificateIssuer:         "CN=sigstore-intermediate,O=sigstore.dev",
		Issuer:                    "https://token.actions.githubusercontent.com",
		BuildTrigger:              "workflow_dispatch",
		BuildConfigURI:            "https://github.com/github/package-security-learning-labs/.github/workflows/npm-publish-with-provenance.yml@refs/heads/main",
		SourceRepositoryURI:       "https://github.com/github/package-security-learning-labs",
		SourceRepositoryDigest:    "4e36c269fbe0e6fd97bce24b084b892d526dc4d2",
		SourceRepositoryRef:       "refs/heads/main",
		RunInvocationURI:          "https://github.com/github/package-security-learning-labs/actions/runs/5389832127/attempts/1",
		NotAfter:                  time.Date(2023, time.June, 27, 12, 44, 16, 0, time.UTC),
	}

	assert.Equal(t, expectedFcs, fcs, "summary mismatch")
}

func TestProvenanceSummary_GitLab(t *testing.T) {
	bundle := testProtobufBundle(t, data.GitLabAlpha01ProtoBundle(t))

	ctx := context.Background()
	summary, err := NewProvenanceSummary(ctx, bundle)
	if err != nil {
		t.Fatalf("failed to get summary: %v", err)
	}

	// In addition to the fields extracted from the certificate in FulcioCertificateSummary
	// we construct the following fields:
	// - ResolvedSourceRepositoryCommitURI
	// - BuildConfigDisplayName
	// - ResolvedBuildConfigURI
	// - TransparencyLogURI
	expectedSummary := ProvenanceSummary{
		SubjectAlternativeName:            "https://gitlab.com/wlynch/npm-provenance-example@refs/heads/main",
		CertificateIssuer:                 "CN=sigstore-intermediate,O=sigstore.dev",
		Issuer:                            "https://gitlab.com",
		IssuerDisplayName:                 "GitLab CI/CD",
		BuildTrigger:                      "web",
		BuildConfigURI:                    "https://gitlab.com/wlynch/npm-provenance-example/-/jobs/4276586778",
		SourceRepositoryURI:               "https://gitlab.com/wlynch/npm-provenance-example",
		SourceRepositoryDigest:            "891e58e84b85b94dcec8618d1ee51f3564022c85",
		SourceRepositoryRef:               "refs/heads/main",
		RunInvocationURI:                  "https://gitlab.com/wlynch/npm-provenance-example/-/pipelines/865814619",
		ExpiresAt:                         time.Date(2023, time.May, 12, 15, 13, 20, 0, time.UTC),
		IncludedAt:                        time.Date(2023, time.May, 12, 15, 03, 21, 0, time.UTC),
		ResolvedSourceRepositoryCommitURI: "https://gitlab.com/wlynch/npm-provenance-example/-/tree/891e58e84b85b94dcec8618d1ee51f3564022c85",
		BuildConfigDisplayName:            ".gitlab-ci.yml",
		ResolvedBuildConfigURI:            "https://gitlab.com/wlynch/npm-provenance-example/-/blob/891e58e84b85b94dcec8618d1ee51f3564022c85/.gitlab-ci.yml",
		TransparencyLogURI:                "https://search.sigstore.dev/?logIndex=20421231",
		ArtifactName:                      "pkg:npm/npm@9.6.6",
	}

	assert.Equal(t, expectedSummary, summary, "provenance summary mismatch")
}

func TestProvenanceSummary_GitLabUpdatedBuildConfigRunInvocation(t *testing.T) {
	bundle := testProtobufBundle(t, data.GitLabUpdatedBuildConfigRunInvocationProtoBundle(t))

	ctx := context.Background()
	summary, err := NewProvenanceSummary(ctx, bundle)
	if err != nil {
		t.Fatalf("failed to get summary: %v", err)
	}

	// In addition to the fields extracted from the certificate in FulcioCertificateSummary
	// we construct the following fields:
	// - ResolvedSourceRepositoryCommitURI
	// - BuildConfigDisplayName
	// - ResolvedBuildConfigURI
	// - TransparencyLogURI
	expectedSummary := ProvenanceSummary{
		SubjectAlternativeName:            "https://gitlab.com/feelepxyz/gitlab-npm-provenance//.gitlab-ci.yml@refs/heads/main",
		CertificateIssuer:                 "CN=sigstore-intermediate,O=sigstore.dev",
		Issuer:                            "https://gitlab.com",
		IssuerDisplayName:                 "GitLab CI/CD",
		BuildTrigger:                      "push",
		BuildConfigURI:                    "https://gitlab.com/feelepxyz/gitlab-npm-provenance//.gitlab-ci.yml@refs/heads/main",
		SourceRepositoryURI:               "https://gitlab.com/feelepxyz/gitlab-npm-provenance",
		SourceRepositoryDigest:            "08f53be3997c251288d6cb2181abd3ac12a94da7",
		SourceRepositoryRef:               "refs/heads/main",
		RunInvocationURI:                  "https://gitlab.com/feelepxyz/gitlab-npm-provenance/-/jobs/4734734047",
		ExpiresAt:                         time.Date(2023, time.July, 25, 9, 32, 10, 0, time.UTC),
		IncludedAt:                        time.Date(2023, time.July, 25, 9, 22, 10, 0, time.UTC),
		ResolvedSourceRepositoryCommitURI: "https://gitlab.com/feelepxyz/gitlab-npm-provenance/-/tree/08f53be3997c251288d6cb2181abd3ac12a94da7",
		BuildConfigDisplayName:            ".gitlab-ci.yml",
		ResolvedBuildConfigURI:            "https://gitlab.com/feelepxyz/gitlab-npm-provenance/-/blob/08f53be3997c251288d6cb2181abd3ac12a94da7/.gitlab-ci.yml",
		TransparencyLogURI:                "https://search.sigstore.dev/?logIndex=28668083",
		ArtifactName:                      "pkg:npm/%40ps-testing/gitlab-npm-provenance@1.0.15",
	}

	assert.Equal(t, expectedSummary, summary, "provenance summary mismatch")
}

func testProtobufBundle(t *testing.T, pb *protobundle.Bundle) *sgbundle.Bundle {
	b, err := sgbundle.NewBundle(pb)
	if err != nil {
		t.Fatal(err)
	}

	return b
}

func TestGetWorkflowRunID(t *testing.T) {
	bundle := testProtobufBundle(t, data.SigstoreJs100ProtoBundle(t))

	expectedID := uint64(4137028816)
	id, err := GetWorkflowRunIDFromBundle(bundle)
	assert.NoError(t, err)
	assert.Equal(t, expectedID, id, "workflow run ID mismatch")

	bundleFromGenerateBuildProvenance := testProtobufBundle(t, data.SigstoreBundleFromGenerateBuildProvenance(t))
	expectedID = uint64(7751033546)
	id, err = GetWorkflowRunIDFromBundle(bundleFromGenerateBuildProvenance)
	assert.NoError(t, err)
	assert.Equal(t, expectedID, id, "workflow run ID mismatch")
}

func TestParseDERString(t *testing.T) {
	input := []byte{0x13, 0x0b, 0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x20, 0x57, 0x6f, 0x72, 0x6c, 0x64}
	expected := "Hello World"
	var actual string
	err := ParseDERString(input, &actual)
	if err != nil {
		t.Errorf("unexpected error: %v", err)
	}
	if actual != expected {
		t.Errorf("unexpected result: got %q, want %q", actual, expected)
	}
}
