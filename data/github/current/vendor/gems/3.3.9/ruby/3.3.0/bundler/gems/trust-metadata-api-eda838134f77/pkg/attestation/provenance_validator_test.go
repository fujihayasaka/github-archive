package attestation

import (
	"testing"

	"github.com/github/trust-metadata-api/testing/data"
	slsa1 "github.com/in-toto/attestation/go/predicates/provenance/v1"
	protobundle "github.com/sigstore/protobuf-specs/gen/pb-go/bundle/v1"
	sgbundle "github.com/sigstore/sigstore-go/pkg/bundle"
	"github.com/sigstore/sigstore-go/pkg/fulcio/certificate"
	"github.com/sigstore/sigstore-go/pkg/verify"
	"github.com/stretchr/testify/assert"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/types/known/structpb"
)

func TestVerifyStatementWithOIDs(t *testing.T) {
	sigstoreBundle := data.SigstoreBundleFromGenerateBuildProvenance(t)

	res := bundleToVerificationResult(sigstoreBundle)
	assert.NotNil(t, res)

	err := VerifyProvenanceStatement(res)
	assert.NoError(t, err)
}

func TestVerifyStatementtWithCustomIssuer(t *testing.T) {
	sigstoreBundle := data.SigstoreBundleWithCustomIssuer(t)
	res := bundleToVerificationResult(sigstoreBundle)
	assert.NotNil(t, res)

	err := VerifyProvenanceStatement(res)
	assert.NoError(t, err)
}

func TestVerifyStatementtWithOIDsWithInvalidStatement(t *testing.T) {
	sigstoreBundle := data.SigstoreBundleFromGenerateBuildProvenanceInvalidOIDs(t)
	res := bundleToVerificationResult(sigstoreBundle)
	assert.NotNil(t, res)

	err := VerifyProvenanceStatement(res)

	assert.Error(t, err)
	assert.Contains(
		t,
		err.Error(),
		"values do not match: https://github.com/wrong/github-early-access/generate-build-provenance != https://github.com/github-early-access/generate-build-provenance",
	)
}

func bundleToVerificationResult(oldbundle *protobundle.Bundle) *verify.VerificationResult {
	bundle, err := sgbundle.NewBundle(oldbundle)
	if err != nil {
		return nil
	}

	envelope, err := bundle.Envelope()
	if err != nil {
		return nil
	}

	statement, err := envelope.Statement()
	if err != nil {
		return nil
	}

	cert, err := leafCertificate(bundle)
	if err != nil {
		return nil
	}

	sc, err := certificate.SummarizeCertificate(cert)

	if err != nil {
		return nil
	}

	return &verify.VerificationResult{
		Statement: statement,
		Signature: &verify.SignatureVerificationResult{
			Certificate: &sc,
		},
	}
}

func TestUnrecognizedPredicateBuiltType(t *testing.T) {
	predicate := &slsa1.Provenance{
		BuildDefinition: &slsa1.BuildDefinition{
			BuildType: "unknown",
		},
	}

	extensions := certificate.Extensions{
		Issuer: GitHubIssuer,
	}
	err := verifySlsaV1ProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "unsupported build type: unknown")
}

func TestInvalidSLSAPredicateSchema(t *testing.T) {
	predicate, err := structpb.NewStruct(map[string]interface{}{"foo": "bar"})
	if err != nil {
		t.Fatal(err)
	}

	extensions := certificate.Extensions{
		Issuer: GitHubIssuer,
	}
	err = verifySlsaV1ProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "predicate is not of type slsa1.ProvenancePredicat")
}

func generateMockSLSAPredicate() *slsa1.Provenance {
	json := []byte(`{
		"buildDefinition": {
			"buildType": "https://slsa-framework.github.io/github-actions-buildtypes/workflow/v1",
			"externalParameters": {
					"workflow": {
					"ref": "refs/heads/main",
					"repository": "https://example.com/repo.git",
					"path": "builds/output"
				}
			},
			"internalParameters": {
				"github": {
					"event_name": "push",
					"repository_id": "12345",
					"repository_owner_id": "67890"
				}
			},
			"resolvedDependencies": [
				{
					"uri": "git+https://example.com/repo.git@refs/heads/main",
					"digest": {
						"gitCommit": "abc123def456"
					}
				}
			]
		},
		"runDetails": {
			"builder": {
				"id": "https://github.com/actions/runner/github-hosted"
			},
			"metadata": {
				"invocationId": "inv123"
			}
		}
	}`)

	predicate := &slsa1.Provenance{}
	if err := protojson.Unmarshal(json, predicate); err != nil {
		return nil
	}
	return predicate
}

func TestVerifySLSAGHAProvenancePredicate(t *testing.T) {
	predicate := generateMockSLSAPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifySLSAGHAProvenancePredicate(predicate, &extensions)
	assert.NoError(t, err)
}

func TestVerifySLSAGHAProvenancePredicateWithWrongSourceRepositoryRef(t *testing.T) {
	predicate := generateMockSLSAPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main?",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifySLSAGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: refs/heads/main != refs/heads/main?")
}

func TestVerifySLSAGHAProvenancePredicateWithWrongSourceRepositoryURI(t *testing.T) {
	predicate := generateMockSLSAPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git?",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifySLSAGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: https://example.com/repo.git != https://example.com/repo.git?")
}

func TestVerifySLSAGHAProvenancePredicateWithWrongBuildConfigURI(t *testing.T) {
	predicate := generateMockSLSAPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output?",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifySLSAGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: builds/output != builds/output?")
}

func TestVerifySLSAGHAProvenancePredicateWithWrongBuildTrigger(t *testing.T) {
	predicate := generateMockSLSAPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push?",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifySLSAGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: push != push?")
}

func TestVerifySLSAGHAProvenancePredicateWithWrongSourceRepositoryIdentifier(t *testing.T) {
	predicate := generateMockSLSAPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345?",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifySLSAGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: 12345 != 12345?")
}

func TestVerifySLSAGHAProvenancePredicateWithWrongSourceRepositoryOwnerIdentifier(t *testing.T) {
	predicate := generateMockSLSAPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890?",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifySLSAGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: 67890 != 67890?")
}

func TestVerifySLSAGHAProvenancePredicateWithWrongSourceRepositoryDigest(t *testing.T) {
	predicate := generateMockSLSAPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456?",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifySLSAGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: abc123def456 != abc123def456?")
}

func TestVerifySLSAGHAProvenancePredicateWithWrongRunInvocationURI(t *testing.T) {
	predicate := generateMockSLSAPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123?",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifySLSAGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: inv123 != inv123?")
}

func TestVerifySLSAGHAProvenancePredicateWithWrongRunnerEnvironment(t *testing.T) {
	predicate := generateMockSLSAPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123?",
		RunnerEnvironment:               "github-hosted?",
	}

	err := verifySLSAGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: https://github.com/actions/runner/github-hosted != https://github.com/actions/runner/github-hosted?")
}

func generateMockGHPredicate() *slsa1.Provenance {
	json := []byte(`{
		"buildDefinition": {
			"buildType": "https://actions.github.io/buildtypes/workflow/v1",
			"externalParameters": {
				"workflow": {
					"ref": "refs/heads/main",
					"repository": "https://example.com/repo.git",
					"path": "builds/output"
				}
			},
			"internalParameters": {
				"github": {
					"event_name": "push",
					"repository_id": "12345",
					"repository_owner_id": "67890",
					"runner_environment":  "github-hosted"
				}
			},
			"resolvedDependencies": [
				{
					"uri": "git+https://example.com/repo.git@refs/heads/main",
					"digest": {
						"gitCommit": "abc123def456"
					}
				}
			]
		},
		"runDetails": {
			"builder": {
				"id": "https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1"
			},
			"metadata": {
				"invocationId": "inv123"
			}
		}
	}`)

	predicate := &slsa1.Provenance{}
	if err := protojson.Unmarshal(json, predicate); err != nil {
		return nil
	}
	return predicate
}

func TestVerifyGHAProvenancePredicate(t *testing.T) {
	predicate := generateMockGHPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildSignerURI:                  "https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifyGHAProvenancePredicate(predicate, &extensions)
	assert.NoError(t, err)
}

func TestVerifyGHAProvenancePredicateWithWrongSourceRepositoryRef(t *testing.T) {
	predicate := generateMockGHPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main?",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildSignerURI:                  "https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifyGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: refs/heads/main != refs/heads/main?")
}

func TestVerifyGHAProvenancePredicateWithWrongSourceRepositoryURI(t *testing.T) {
	predicate := generateMockGHPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git?",
		BuildSignerURI:                  "https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifyGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: https://example.com/repo.git != https://example.com/repo.git?")
}

func TestVerifyGHAProvenancePredicateWithWrongBuildConfigURI(t *testing.T) {
	predicate := generateMockGHPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildSignerURI:                  "https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output?",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifyGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: builds/output != builds/output?")
}

func TestVerifyGHAProvenancePredicateWithWrongBuildTrigger(t *testing.T) {
	predicate := generateMockGHPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildSignerURI:                  "https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push?",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifyGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: push != push?")
}

func TestVerifyGHAProvenancePredicateWithWrongSourceRepositoryIdentifier(t *testing.T) {
	predicate := generateMockGHPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildSignerURI:                  "https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345?",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifyGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: 12345 != 12345?")
}

func TestVerifyGHAProvenancePredicateWithWrongRunnerEnvironment(t *testing.T) {
	predicate := generateMockGHPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildSignerURI:                  "https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123?",
		RunnerEnvironment:               "github-hosted?",
	}

	err := verifyGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: github-hosted != github-hosted")
}

func TestVerifyGHAProvenancePredicateWithWrongSourceRepositoryOwnerIdentifier(t *testing.T) {
	predicate := generateMockGHPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildSignerURI:                  "https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890?",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifyGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: 67890 != 67890?")
}

func TestVerifyGHAProvenancePredicateWithWrongSourceRepositoryDigest(t *testing.T) {
	predicate := generateMockGHPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildSignerURI:                  "https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456?",
		RunInvocationURI:                "inv123",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifyGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: abc123def456 != abc123def456?")
}

func TestVerifyGHAProvenancePredicateWithWrongBuilderId(t *testing.T) {
	predicate := generateMockGHPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildSignerURI:                  "oops",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123?",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifyGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1 != oops")
}

func TestVerifyGHAProvenancePredicateWithWrongRunInvocationURI(t *testing.T) {
	predicate := generateMockGHPredicate()

	extensions := certificate.Extensions{
		SourceRepositoryRef:             "refs/heads/main",
		SourceRepositoryURI:             "https://example.com/repo.git",
		BuildSignerURI:                  "https://example.com/org/repo/.github/workflows/main.yml@refs/tags/v1",
		BuildConfigURI:                  "https://example.com/repo.git/builds/output",
		BuildTrigger:                    "push",
		SourceRepositoryIdentifier:      "12345",
		SourceRepositoryOwnerIdentifier: "67890",
		SourceRepositoryDigest:          "abc123def456",
		RunInvocationURI:                "inv123?",
		RunnerEnvironment:               "github-hosted",
	}

	err := verifyGHAProvenancePredicate(predicate, &extensions)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "values do not match: inv123 != inv123?")
}
