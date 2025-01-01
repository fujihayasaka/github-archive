package secureref

import (
	"context"
	"testing"

	githubgo "github.com/google/go-github/v25/github"
	"github.com/stretchr/testify/assert"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/utils/testutils"
)

func TestGetFullyQualifiedSecureRef(t *testing.T) {
	type testInput struct {
		name             string
		isFullyQualified bool
		expectError      bool
		errorType        string
		baseRef          string
		baseSHA          string
		eventName        string
	}

	inputs := []testInput{
		{
			name:             "Input ref is a valid fully qualified ref",
			isFullyQualified: true,
			expectError:      false,
			errorType:        "",
			baseRef:          "refs/heads/main",
			baseSHA:          "10f230cfacc4a83227ddd04269a10aec5e3ff8dbe843ddc77615c6163eed9de0",
			eventName:        "pull_request",
		},
		{
			name:             "Input ref is a valid ref but is not fully qualified",
			isFullyQualified: false,
			expectError:      false,
			errorType:        "",
			baseRef:          "main",
			baseSHA:          "10f230cfacc4a83227ddd04269a10aec5e3ff8dbe843ddc77615c6163eed9de0",
			eventName:        "pull_request",
		},
		{
			name:             "Input ref is not valid and ref matches the SHA",
			isFullyQualified: false,
			expectError:      true,
			errorType:        "SHA",
			baseRef:          "10f230cfacc4a83227ddd04269a10aec5e3ff8dbe843ddc77615c6163eed9de0",
			baseSHA:          "10f230cfacc4a83227ddd04269a10aec5e3ff8dbe843ddc77615c6163eed9de0",
			eventName:        "pull_request",
		},
		{
			name:             "Input ref is not valid and is a forked PR",
			isFullyQualified: false,
			expectError:      true,
			errorType:        "PR",
			baseRef:          "refs/pull/main",
			baseSHA:          "10f230cfacc4a83227ddd04269a10aec5e3ff8dbe843ddc77615c6163eed9de0",
			eventName:        "pull_request",
		},
		{
			name:             "Input ref is not valid and matches the suffix of a git describe",
			isFullyQualified: false,
			expectError:      true,
			errorType:        "GitDescribe",
			// The attack works because when a branch ref is called something-123-gdeadbeef,
			// the name is interpreted by git rev-parse as a string in the git-describe format, resolving to a commit with the shorthash deadbeef.
			// See issue: https://github.com/github/c2c-actions/issues/4577
			baseRef:   "something-123-gdeadbeef",
			baseSHA:   "10f230cfacc4a83227ddd04269a10aec5e3ff8dbe843ddc77615c6163eed9de0",
			eventName: "pull_request",
		},
	}

	for _, input := range inputs {
		t.Run(input.name, func(t *testing.T) {
			ctx := context.Background()
			rlogger := testutils.NewRecordingLogger()
			obs := observability.New(rlogger.Logger, statter.NullStatter())

			pre := &githubgo.PullRequestBranch{
				SHA: &input.baseSHA,
				Ref: &input.baseRef,
			}

			// fqRef, err :=  GetFullyQualifiedSecureRef(ctx, obs.Logger, input.baseRef, input.baseSHA, input.eventName)
			fqRef, err := GetFullyQualifiedSecureRef(ctx, obs.Logger, pre, input.eventName)

			if !input.expectError {
				// If the input is a valid fully qualified ref, then we should not expect an error
				if input.isFullyQualified {
					assert.Equal(t, input.baseRef, fqRef.String())
					assert.Equal(t, input.expectError, err != nil)
				} else {
					// If the input is not a valid fully qualified ref, but is valid, then we should prefix the ref with with refs/heads
					assert.Equal(t, "refs/heads/main", fqRef.String())
					assert.Equal(t, input.expectError, err != nil)
				}
			} else {
				switch input.errorType {
				case "SHA":
					assert.Equal(t, "", fqRef.String())
					assert.Equal(t, input.expectError, err != nil)
					assert.Contains(t, rlogger.String(), "Base ref can't be a commit sha")
				case "PR":
					assert.Equal(t, "", fqRef.String())
					assert.Equal(t, input.expectError, err != nil)
					assert.Contains(t, rlogger.String(), "Base ref can't be a pull request ref")
				case "GitDescribe":
					assert.Equal(t, "", fqRef.String())
					assert.Equal(t, input.expectError, err != nil)
					assert.Contains(t, rlogger.String(), "Base ref suffix can't match a git describe suffix")
				}
			}
		})
	}
}
