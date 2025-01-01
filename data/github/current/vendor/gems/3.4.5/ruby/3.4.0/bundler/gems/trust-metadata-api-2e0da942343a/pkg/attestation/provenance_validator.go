package attestation

import (
	"errors"
	"fmt"
	"strings"

	slsa1 "github.com/in-toto/attestation/go/predicates/provenance/v1"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/reflect/protoreflect"

	"github.com/sigstore/sigstore-go/pkg/fulcio/certificate"
	"github.com/sigstore/sigstore-go/pkg/verify"
)

const (
	PredicateSLSAProvenance = "https://slsa.dev/provenance/v1"
	PredicateRelease        = "https://in-toto.io/attestation/release/v0.1"
	GitHubIssuer            = "https://token.actions.githubusercontent.com"
	// Legacy build type for GitHub Actions
	SLSAGitHubActionsProvenanceBuildType = "https://slsa-framework.github.io/github-actions-buildtypes/workflow/v1"
	// Official build type for GitHub Actions
	GitHubActionsProvenanceBuildType = "https://actions.github.io/buildtypes/workflow/v1"
)

func compare(predicateValue interface{}, extensionsValue string) error {
	var v string
	var ok bool

	if v, ok = predicateValue.(string); !ok {
		return fmt.Errorf("required predicate value is unset")
	}

	if v != extensionsValue {
		return fmt.Errorf("values do not match: %s != %s", v, extensionsValue)
	}
	return nil
}

// Verify provenance predicate for GitHub Actions build type
func verifyGHAProvenancePredicate(predicate *slsa1.Provenance, extensions *certificate.Extensions) error {
	if buildDefinition := predicate.BuildDefinition; buildDefinition != nil {
		if externalParams := buildDefinition.ExternalParameters; externalParams != nil {
			externalParamsMap := externalParams.AsMap()
			if workflow, ok := externalParamsMap["workflow"].(map[string]interface{}); ok {
				// compare 'buildDefinition.externalParameters.workflow.ref' with 'SourceRepositoryRef'
				if err := compare(workflow["ref"], extensions.SourceRepositoryRef); err != nil {
					return err
				}

				// compare 'buildDefinition.externalParameters.workflow.repository' with 'SourceRepositoryURI'
				if err := compare(workflow["repository"], extensions.SourceRepositoryURI); err != nil {
					return err
				}

				// compare 'buildDefinition.externalParameters.workflow.path' with 'BuildConfigURI'
				expectedWorkflowPath := strings.Split(strings.ReplaceAll(extensions.BuildConfigURI, extensions.SourceRepositoryURI+"/", ""), "@")[0]
				if err := compare(workflow["path"], expectedWorkflowPath); err != nil {
					return err
				}
			} else {
				return errors.New("buildDefinition.externalParameters.workflow not found")
			}
		} else {
			return errors.New("buildDefinition.externalParameters not found")
		}

		if internalParameters := buildDefinition.InternalParameters; internalParameters != nil {
			internalParamsMap := internalParameters.AsMap()
			if github, ok := internalParamsMap["github"].(map[string]interface{}); ok {
				// compare 'buildDefinition.internalParameters.github.event_name' with 'BuildTrigger'
				if err := compare(github["event_name"], extensions.BuildTrigger); err != nil {
					return err
				}

				// compare 'buildDefinition.internalParameters.github.repository_id' with 'SourceRepositoryIdentifier'
				if err := compare(github["repository_id"], extensions.SourceRepositoryIdentifier); err != nil {
					return err
				}

				// compare 'buildDefinition.internalParameters.github.repository_owner_id' with 'SourceRepositoryOwnerIdentifier'
				if err := compare(github["repository_owner_id"], extensions.SourceRepositoryOwnerIdentifier); err != nil {
					return err
				}

				// compare 'buildDefinition.internalParameters.github.runner_environment' with 'RunnerEnvironment'
				if err := compare(github["runner_environment"], extensions.RunnerEnvironment); err != nil {
					return err
				}
			} else {
				return errors.New("buildDefinition.internalParameters.github not found")
			}
		} else {
			return errors.New("buildDefinition.internalParameters not found")
		}

		if len(buildDefinition.ResolvedDependencies) > 0 {
			// compare 'buildDefinition.resolvedDependencies[0].uri' with 'SourceRepositoryURI' and 'expectedSourceUri'
			expectedSourceURI := "git+" + extensions.SourceRepositoryURI + "@" + extensions.SourceRepositoryRef
			if err := compare(buildDefinition.ResolvedDependencies[0].Uri, expectedSourceURI); err != nil {
				return err
			}

			// compare 'buildDefinition.resolvedDependencies[0].digest.gitCommit' with 'SourceRepositoryDigest'
			if err := compare(buildDefinition.ResolvedDependencies[0].Digest["gitCommit"], extensions.SourceRepositoryDigest); err != nil {
				return err
			}
		} else {
			return errors.New("buildDefinition.resolvedDependencies not found")
		}
	} else {
		return errors.New("buildDefinition not found")
	}

	if runDetails := predicate.RunDetails; runDetails != nil {
		if builder := runDetails.Builder; builder != nil {
			// compare 'runDetails.builder.id' with 'BuildSignerURI'
			if err := compare(builder.Id, extensions.BuildSignerURI); err != nil {
				return err
			}
		} else {
			return errors.New("runDetails.builder not found")
		}

		if metadata := runDetails.Metadata; metadata != nil {
			// compare 'runDetails.metadata.invocationId' with 'RunInvocationURI'
			return compare(metadata.InvocationId, extensions.RunInvocationURI)
		}
		return errors.New("runDetails.metadata not found")
	}
	return errors.New("runDetails not found")
}

// Verify provenance predicate for SLSA-hosted GitHub Actions build type
func verifySLSAGHAProvenancePredicate(predicate *slsa1.Provenance, extensions *certificate.Extensions) error {
	if buildDefinition := predicate.BuildDefinition; buildDefinition != nil {
		if externalParams := buildDefinition.ExternalParameters; externalParams != nil {
			externalParamsMap := externalParams.AsMap()
			if workflow, ok := externalParamsMap["workflow"].(map[string]interface{}); ok {
				// compare 'buildDefinition.externalParameters.workflow.ref' with 'SourceRepositoryRef'
				if err := compare(workflow["ref"], extensions.SourceRepositoryRef); err != nil {
					return err
				}

				// compare 'buildDefinition.externalParameters.workflow.repository' with 'SourceRepositoryURI'
				if err := compare(workflow["repository"], extensions.SourceRepositoryURI); err != nil {
					return err
				}

				// compare 'buildDefinition.externalParameters.workflow.path' with 'BuildConfigURI'
				expectedWorkflowPath := strings.Split(strings.ReplaceAll(extensions.BuildConfigURI, extensions.SourceRepositoryURI+"/", ""), "@")[0]
				if err := compare(workflow["path"], expectedWorkflowPath); err != nil {
					return err
				}
			} else {
				return errors.New("workflow not found")
			}
		} else {
			return errors.New("externalParameters not found")
		}

		if internalParameters := buildDefinition.InternalParameters; internalParameters != nil {
			internalParamsMap := internalParameters.AsMap()
			if github, ok := internalParamsMap["github"].(map[string]interface{}); ok {
				// compare 'buildDefinition.internalParameters.github.event_name' with 'BuildTrigger'
				if err := compare(github["event_name"], extensions.BuildTrigger); err != nil {
					return err
				}

				// compare 'buildDefinition.internalParameters.github.repository_id' with 'SourceRepositoryIdentifier'
				if err := compare(github["repository_id"], extensions.SourceRepositoryIdentifier); err != nil {
					return err
				}

				// compare 'buildDefinition.internalParameters.github.repository_owner_id' with 'SourceRepositoryOwnerIdentifier'
				if err := compare(github["repository_owner_id"], extensions.SourceRepositoryOwnerIdentifier); err != nil {
					return err
				}
			} else {
				return errors.New("github not found")
			}
		} else {
			return errors.New("internalParameters not found")
		}

		if len(buildDefinition.ResolvedDependencies) > 0 {
			// compare 'buildDefinition.resolvedDependencies[0].uri' with 'SourceRepositoryURI' and 'expectedSourceUri'
			expectedSourceURI := "git+" + extensions.SourceRepositoryURI + "@" + extensions.SourceRepositoryRef
			if err := compare(buildDefinition.ResolvedDependencies[0].Uri, expectedSourceURI); err != nil {
				return err
			}

			// compare 'buildDefinition.resolvedDependencies[0].digest.gitCommit' with 'SourceRepositoryDigest'
			if err := compare(buildDefinition.ResolvedDependencies[0].Digest["gitCommit"], extensions.SourceRepositoryDigest); err != nil {
				return err
			}
		} else {
			return errors.New("resolvedDependencies not found")
		}
	} else {
		return errors.New("buildDefinition not found")
	}

	if runDetails := predicate.RunDetails; runDetails != nil {
		if builder := runDetails.Builder; builder != nil {
			expectedBuilderID := "https://github.com/actions/runner/" + extensions.RunnerEnvironment
			if err := compare(builder.Id, expectedBuilderID); err != nil {
				return err
			}
		} else {
			return errors.New("runDetails.builder not found")
		}

		if metadata := runDetails.Metadata; metadata != nil {
			// compare 'runDetails.metadata.invocationId' with 'RunInvocationURI'
			return compare(metadata.InvocationId, extensions.RunInvocationURI)
		}
		return errors.New("runDetails.metadata not found")
	}
	return errors.New("runDetails not found")
}

func verifySlsaV1ProvenancePredicate(predicate protoreflect.ProtoMessage, extensions *certificate.Extensions) error {
	b, err := protojson.Marshal(predicate)
	if err != nil {
		return err
	}
	// unmarshall byte to  slsa1.ProvenancePredicate
	var slsa1Predicate slsa1.Provenance
	err = protojson.Unmarshal(b, &slsa1Predicate)
	if err != nil {
		return errors.New("predicate is not of type slsa1.ProvenancePredicate")
	}

	// Ensure BuildDefinition is not nil before accessing BuildType
	if slsa1Predicate.BuildDefinition == nil {
		return errors.New("build definition is nil")
	}

	// Must be one of the two supported SLSA provenance predicate build types
	switch slsa1Predicate.BuildDefinition.BuildType {
	case SLSAGitHubActionsProvenanceBuildType:
		return verifySLSAGHAProvenancePredicate(&slsa1Predicate, extensions)
	case GitHubActionsProvenanceBuildType:
		return verifyGHAProvenancePredicate(&slsa1Predicate, extensions)
	default:
		return fmt.Errorf("unsupported build type: %s", slsa1Predicate.BuildDefinition.BuildType)
	}
}

func VerifyProvenanceStatement(res *verify.VerificationResult) error {
	if res.Statement == nil {
		return errors.New("missing verified statement")
	}
	statement := res.Statement

	// Only verify the provenace statement for slsa1 predicate type
	if statement.PredicateType == PredicateSLSAProvenance {
		if res.Signature == nil {
			return errors.New("missing verified signature")
		}

		if res.Signature.Certificate == nil {
			return errors.New("missing verified certificate")
		}

		return verifySlsaV1ProvenancePredicate(res.Statement.Predicate, &res.Signature.Certificate.Extensions)
	}
	return nil
}
