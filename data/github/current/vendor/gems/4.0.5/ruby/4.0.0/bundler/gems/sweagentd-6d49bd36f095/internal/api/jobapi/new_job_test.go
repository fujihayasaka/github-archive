package jobapi

import (
	"encoding/json"
	"strings"
	"testing"
	"unicode/utf8"

	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/jobservice"
	gg "github.com/google/go-github/v75/github"
	"github.com/stretchr/testify/require"
)

func TestNewJobAPIRequest_validate_UTF8CharacterCounting(t *testing.T) {
	// Create a string with multi-byte UTF-8 characters
	// Each emoji is 4 bytes in UTF-8, but counts as 1 character
	// So 30000 emojis = 120,000 bytes but 30000 characters
	multiByteString := strings.Repeat("🔥", 30000) // This emoji is 4 bytes in UTF-8

	// Verify our test string has the expected characteristics
	require.Equal(t, 120000, len(multiByteString), "Test string should be 120000 bytes")
	require.Equal(t, 30000, utf8.RuneCountInString(multiByteString), "Test string should be 30000 UTF-8 characters")

	repo := &gg.Repository{
		DefaultBranch: stringPtr("main"),
	}

	t.Run("fixed behavior - allows 30000 UTF-8 characters regardless of byte count", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: multiByteString,
		}

		err := args.validate(repo)
		// After the fix: 30000 UTF-8 characters should be allowed even if they are 120000 bytes
		require.NoError(t, err, "30000 UTF-8 characters should be allowed regardless of byte count")
	})

	t.Run("ASCII characters at exactly the limit should pass", func(t *testing.T) {
		asciiString := strings.Repeat("a", 30000)

		args := &NewJobAPIRequest{
			ProblemStatement: asciiString,
		}

		err := args.validate(repo)
		require.NoError(t, err, "30000 ASCII characters should be allowed")
	})

	t.Run("ASCII characters over the limit should fail", func(t *testing.T) {
		asciiString := strings.Repeat("a", 30001)

		args := &NewJobAPIRequest{
			ProblemStatement: asciiString,
		}

		err := args.validate(repo)
		require.Error(t, err, "30001 ASCII characters should be rejected")
		require.Contains(t, err.Error(), "exceeds maximum length")
	})

	t.Run("fixed behavior - should reject over 30000 UTF-8 characters", func(t *testing.T) {
		// Create 30001 UTF-8 characters
		tooManyCharsString := multiByteString + "🔥"

		args := &NewJobAPIRequest{
			ProblemStatement: tooManyCharsString,
		}

		err := args.validate(repo)
		require.Error(t, err, "30001 UTF-8 characters should be rejected")
		require.Contains(t, err.Error(), "exceeds maximum length")
		require.Contains(t, err.Error(), "30001", "Error message should show character count, not byte count")
	})
}

func TestNewJobAPIRequest_validate_PullRequestHeadRef(t *testing.T) {
	repo := &gg.Repository{
		DefaultBranch: stringPtr("main"),
	}

	t.Run("prefixed head_ref is allowed", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: "Test problem",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "copilot/feature-branch",
				},
			},
		}

		err := args.validate(repo)
		require.NoError(t, err, "Valid head_ref with correct prefix should pass validation")
	})

	t.Run("non-prefixed head_ref is allowed", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: "Test problem",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "feature-branch",
				},
			},
		}
		err := args.validate(repo)
		require.NoError(t, err, "head_ref without prefix should pass validation")
	})

	t.Run("empty head_ref should pass", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: "Test problem",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "",
				},
			},
		}
		err := args.validate(repo)
		require.NoError(t, err, "Empty head_ref should pass validation")
	})

	t.Run("nil pull_request should pass", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: "Test problem",
			Features: &EnvironmentFeatures{
				PullRequest: nil,
			},
		}
		err := args.validate(repo)
		require.NoError(t, err, "nil pull_request should pass validation")
	})

	t.Run("default branch is blocked", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: "Test problem",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "main",
				},
			},
		}
		err := args.validate(repo)
		require.Error(t, err, "Default branch should be rejected")
		require.Contains(t, err.Error(), "matches the repository default branch")
	})

	t.Run("prefixed head_ref is still allowed", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: "Test problem",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "copilot/feature-branch",
				},
			},
		}
		err := args.validate(repo)
		require.NoError(t, err, "Prefixed head_ref should still pass validation")
	})

	t.Run("refs/heads/ prefix is normalized before default branch check", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: "Test problem",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "refs/heads/main",
				},
			},
		}
		err := args.validate(repo)
		require.Error(t, err, "refs/heads/main should be normalized and rejected as default branch")
		require.Contains(t, err.Error(), "matches the repository default branch")
	})

	t.Run("refs/heads/ prefix is normalized for non-default branch", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: "Test problem",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "refs/heads/feature-branch",
				},
			},
		}
		err := args.validate(repo)
		require.NoError(t, err, "refs/heads/feature-branch should be normalized and allowed")
		require.Equal(t, "feature-branch", args.Features.PullRequest.HeadRef, "HeadRef should be normalized to bare branch name")
	})

	t.Run("fork-qualified default branch is blocked without altering head_ref", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: "Test problem",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "octo:main",
				},
			},
		}
		err := args.validate(repo)
		require.Error(t, err, "fork-qualified default branch should be rejected")
		require.Contains(t, err.Error(), "matches the repository default branch")
		require.Equal(t, "octo:main", args.Features.PullRequest.HeadRef, "HeadRef should remain unchanged for PR lookup")
	})

	t.Run("fork-qualified refs/heads/ default branch is blocked without altering head_ref", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: "Test problem",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					HeadRef: "octo:refs/heads/main",
				},
			},
		}
		err := args.validate(repo)
		require.Error(t, err, "fork-qualified refs/heads/main should be rejected")
		require.Contains(t, err.Error(), "matches the repository default branch")
		require.Equal(t, "octo:refs/heads/main", args.Features.PullRequest.HeadRef, "HeadRef should remain unchanged for PR lookup")
	})
}

func TestNewJobAPIRequest_validate_Archived(t *testing.T) {
	repo := &gg.Repository{
		Archived:      gg.Ptr(true),
		DefaultBranch: stringPtr("main"),
	}

	t.Run("invalid if repo is archived", func(t *testing.T) {
		args := &NewJobAPIRequest{
			ProblemStatement: "Test problem",
		}
		err := args.validate(repo)
		require.Error(t, err, "validate should fail for archived repository")
		require.Contains(t, err.Error(), "repository is archived")
	})
}

func TestUtilityFunctions_UTF8(t *testing.T) {
	// Create test strings with multi-byte UTF-8 characters
	multiByteString := strings.Repeat("🔥", 20) // 20 UTF-8 characters, 80 bytes
	require.Equal(t, 80, len(multiByteString), "Test string should be 80 bytes")
	require.Equal(t, 20, utf8.RuneCountInString(multiByteString), "Test string should be 20 UTF-8 characters")

	t.Run("truncate function with UTF-8", func(t *testing.T) {
		// Test normal truncation
		result := truncate(multiByteString, 15)
		require.Equal(t, 15, utf8.RuneCountInString(result), "Should truncate to exactly 15 UTF-8 characters")
		require.Contains(t, result, "...", "Should contain ellipsis")

		// Test no truncation needed
		result = truncate(multiByteString, 25)
		require.Equal(t, multiByteString, result, "Should not truncate when limit is higher")

		// Test edge case with small limit
		result = truncate(multiByteString, 3)
		require.Equal(t, 3, utf8.RuneCountInString(result), "Should handle small limits correctly")
	})

	t.Run("capLength function with UTF-8", func(t *testing.T) {
		// Test normal capping
		result := capLength(multiByteString, 15)
		require.Equal(t, 15, utf8.RuneCountInString(result), "Should cap to exactly 15 UTF-8 characters")
		require.NotContains(t, result, "...", "Should not contain ellipsis")

		// Test no capping needed
		result = capLength(multiByteString, 25)
		require.Equal(t, multiByteString, result, "Should not cap when limit is higher")
	})
}

func TestNewJobAPIRequest_UnmarshalJSON(t *testing.T) {
	t.Run("deprecated pull_request at root is moved to features", func(t *testing.T) {
		jsonData := []byte(`{
			"problem_statement": "test problem",
			"pull_request": {
				"title": "Test PR",
				"body_placeholder": "Test body",
				"body_suffix": "Fixes #123"
			}
		}`)

		var req NewJobAPIRequest
		err := json.Unmarshal(jsonData, &req)
		require.NoError(t, err)

		require.Equal(t, "test problem", req.ProblemStatement)

		require.NotNil(t, req.Features, "PullRequest should be moved to Features")
		require.NotNil(t, req.Features.PullRequest, "PullRequest should be moved to Features")
		require.Equal(t, "Test PR", req.Features.PullRequest.Title)
		require.Equal(t, "Test body", req.Features.PullRequest.BodyPlaceholder)
		require.Equal(t, "Fixes #123", req.Features.PullRequest.BodySuffix)
	})

	t.Run("features.pull_request takes precedence over deprecated root pull_request", func(t *testing.T) {
		jsonData := []byte(`{
			"problem_statement": "test problem",
			"pull_request": {
				"title": "Deprecated PR",
				"body_placeholder": "Old body"
			},
			"features": {
				"pull_request": {
					"title": "New PR",
					"body_placeholder": "New body"
				}
			}
		}`)

		var req NewJobAPIRequest
		err := json.Unmarshal(jsonData, &req)
		require.NoError(t, err)

		require.Equal(t, "test problem", req.ProblemStatement)

		require.NotNil(t, req.Features.PullRequest, "PullRequest should exist in Features")
		require.Equal(t, "New PR", req.Features.PullRequest.Title, "Should use features.pull_request, not deprecated root pull_request")
		require.Equal(t, "New body", req.Features.PullRequest.BodyPlaceholder)
	})

	t.Run("new format with features.pull_request works correctly", func(t *testing.T) {
		jsonData := []byte(`{
			"problem_statement": "test problem",
			"features": {
				"pull_request": {
					"title": "New Format PR",
					"body_placeholder": "New format body",
					"base_ref": "main",
					"head_ref": "feature-branch"
				}
			}
		}`)

		var req NewJobAPIRequest
		err := json.Unmarshal(jsonData, &req)
		require.NoError(t, err)

		require.Equal(t, "test problem", req.ProblemStatement)

		require.NotNil(t, req.Features.PullRequest)
		require.Equal(t, "New Format PR", req.Features.PullRequest.Title)
		require.Equal(t, "New format body", req.Features.PullRequest.BodyPlaceholder)
		require.Equal(t, "main", req.Features.PullRequest.BaseRef)
		require.Equal(t, "feature-branch", req.Features.PullRequest.HeadRef)
	})

	t.Run("no pull_request fields should result in nil", func(t *testing.T) {
		jsonData := []byte(`{
			"problem_statement": "test problem",
			"features": {
				"branch": {
					"name": "test-branch"
				}
			}
		}`)

		var req NewJobAPIRequest
		err := json.Unmarshal(jsonData, &req)
		require.NoError(t, err)

		require.Equal(t, "test problem", req.ProblemStatement)
		require.Nil(t, req.Features.PullRequest, "PullRequest should be nil when not provided")
		require.NotNil(t, req.Features.Branch, "Branch should still be populated")
	})

	t.Run("explicit null pull_request should result in nil", func(t *testing.T) {
		jsonData := []byte(`{
			"problem_statement": "test problem",
			"features": {
				"pull_request": null
			}
		}`)

		var req NewJobAPIRequest
		err := json.Unmarshal(jsonData, &req)
		require.NoError(t, err)

		require.Equal(t, "test problem", req.ProblemStatement)
		require.Nil(t, req.Features.PullRequest, "PullRequest should be nil when explicitly set to null")
	})

	t.Run("all pull_request fields are correctly unmarshaled from deprecated location", func(t *testing.T) {
		jsonData := []byte(`{
			"problem_statement": "test problem",
			"pull_request": {
				"title": "Complete PR",
				"body_placeholder": "Complete body",
				"body_suffix": "Fixes #456",
				"base_ref": "develop",
				"head_ref": "feature-x",
				"labels": ["bug", "enhancement"]
			}
		}`)

		var req NewJobAPIRequest
		err := json.Unmarshal(jsonData, &req)
		require.NoError(t, err)

		require.Equal(t, "test problem", req.ProblemStatement)

		pr := req.Features.PullRequest
		require.NotNil(t, pr)
		require.Equal(t, "Complete PR", pr.Title)
		require.Equal(t, "Complete body", pr.BodyPlaceholder)
		require.Equal(t, "Fixes #456", pr.BodySuffix)
		require.Equal(t, "develop", pr.BaseRef)
		require.Equal(t, "feature-x", pr.HeadRef)
		require.Equal(t, []string{"bug", "enhancement"}, pr.Labels)
	})

	t.Run("invalid JSON returns error", func(t *testing.T) {
		jsonData := []byte(`{
			"problem_statement": "test problem",
			"pull_request": {
				"title": "Invalid
			}
		}`)

		var req NewJobAPIRequest
		err := json.Unmarshal(jsonData, &req)
		require.Error(t, err, "Should return error for invalid JSON")
	})
}

func TestNewJobAPIRequest_MarshalUnmarshal_AllProperties(t *testing.T) {
	t.Run("all properties are preserved through marshal/unmarshal cycle", func(t *testing.T) {
		original := &NewJobAPIRequest{
			ProblemStatement:  "Fix the bug in the authentication module",
			ContentFilterMode: "strict",
			RunName:           "test-run-123",
			EventType:         "issue_assignment",
			EventURL:          "https://github.com/owner/repo/issues/123",
			EventIdentifiers:  []string{"issue-123", "user-456"},
			EventContent:      "test event content",
			Features: &EnvironmentFeatures{
				Branch: &BranchFeature{
					Name:    "fix-auth-bug",
					BaseRef: "develop",
				},
				PullRequest: &PullRequestFeature{
					Title:           "Fix authentication bug",
					BodyPlaceholder: "This PR fixes the authentication bug",
					BodySuffix:      "Fixes #123",
					BaseRef:         "main",
					HeadRef:         "fix-auth-bug",
					Labels:          []string{"bug", "security"},
				},
			},
			CustomAgent: "security-agent",
		}

		// Marshal to JSON
		jsonData, err := json.Marshal(original)
		require.NoError(t, err)

		// Unmarshal back
		var unmarshaled NewJobAPIRequest
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		// Verify all top-level fields
		require.Equal(t, original.ProblemStatement, unmarshaled.ProblemStatement)
		require.Equal(t, original.ContentFilterMode, unmarshaled.ContentFilterMode)
		require.Equal(t, original.RunName, unmarshaled.RunName)
		require.Equal(t, original.EventType, unmarshaled.EventType)
		require.Equal(t, original.EventURL, unmarshaled.EventURL)
		require.Equal(t, original.EventIdentifiers, unmarshaled.EventIdentifiers)
		require.Equal(t, original.EventContent, unmarshaled.EventContent)
		require.Equal(t, original.CustomAgent, unmarshaled.CustomAgent)

		// Verify BranchFeature
		require.NotNil(t, unmarshaled.Features.Branch)
		require.Equal(t, original.Features.Branch.Name, unmarshaled.Features.Branch.Name)
		require.Equal(t, original.Features.Branch.BaseRef, unmarshaled.Features.Branch.BaseRef)

		// Verify PullRequestFeature
		require.NotNil(t, unmarshaled.Features.PullRequest)
		require.Equal(t, original.Features.PullRequest.Title, unmarshaled.Features.PullRequest.Title)
		require.Equal(t, original.Features.PullRequest.BodyPlaceholder, unmarshaled.Features.PullRequest.BodyPlaceholder)
		require.Equal(t, original.Features.PullRequest.BodySuffix, unmarshaled.Features.PullRequest.BodySuffix)
		require.Equal(t, original.Features.PullRequest.BaseRef, unmarshaled.Features.PullRequest.BaseRef)
		require.Equal(t, original.Features.PullRequest.HeadRef, unmarshaled.Features.PullRequest.HeadRef)
		require.Equal(t, original.Features.PullRequest.Labels, unmarshaled.Features.PullRequest.Labels)
	})

	t.Run("minimal request with only required fields", func(t *testing.T) {
		original := &NewJobAPIRequest{
			ProblemStatement: "Fix the bug",
		}

		jsonData, err := json.Marshal(original)
		require.NoError(t, err)

		var unmarshaled NewJobAPIRequest
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		require.Equal(t, original.ProblemStatement, unmarshaled.ProblemStatement)
		require.Empty(t, unmarshaled.ContentFilterMode)
		require.Empty(t, unmarshaled.RunName)
		require.Empty(t, unmarshaled.EventType)
		require.Empty(t, unmarshaled.EventURL)
		require.Nil(t, unmarshaled.EventIdentifiers)
		require.Empty(t, unmarshaled.EventContent)
		require.Nil(t, unmarshaled.Features)
		require.Empty(t, unmarshaled.CustomAgent)
	})

	t.Run("partial features - only branch", func(t *testing.T) {
		original := &NewJobAPIRequest{
			ProblemStatement: "Create new feature",
			Features: &EnvironmentFeatures{
				Branch: &BranchFeature{
					Name:    "new-feature",
					BaseRef: "main",
				},
			},
		}

		jsonData, err := json.Marshal(original)
		require.NoError(t, err)

		var unmarshaled NewJobAPIRequest
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		require.Equal(t, original.ProblemStatement, unmarshaled.ProblemStatement)
		require.NotNil(t, unmarshaled.Features.Branch)
		require.Equal(t, "new-feature", unmarshaled.Features.Branch.Name)
		require.Equal(t, "main", unmarshaled.Features.Branch.BaseRef)
		require.Nil(t, unmarshaled.Features.PullRequest)
	})

	t.Run("partial features - only pull request", func(t *testing.T) {
		original := &NewJobAPIRequest{
			ProblemStatement: "Create pull request",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					Title:           "New PR",
					BodyPlaceholder: "Description",
				},
			},
		}

		jsonData, err := json.Marshal(original)
		require.NoError(t, err)

		var unmarshaled NewJobAPIRequest
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		require.Equal(t, original.ProblemStatement, unmarshaled.ProblemStatement)
		require.Nil(t, unmarshaled.Features.Branch)
		require.NotNil(t, unmarshaled.Features.PullRequest)
		require.Equal(t, "New PR", unmarshaled.Features.PullRequest.Title)
		require.Equal(t, "Description", unmarshaled.Features.PullRequest.BodyPlaceholder)
	})

	t.Run("empty arrays serialize and deserialize correctly", func(t *testing.T) {
		original := &NewJobAPIRequest{
			ProblemStatement: "Test empty collections",
			EventIdentifiers: []string{},
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					Labels: []string{},
				},
			},
		}

		jsonData, err := json.Marshal(original)
		require.NoError(t, err)

		var unmarshaled NewJobAPIRequest
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		require.Equal(t, original.ProblemStatement, unmarshaled.ProblemStatement)
		// Note: Empty JSON arrays unmarshal to nil slices in Go, not empty slices
		// This is expected behavior and both are semantically equivalent
		require.Empty(t, unmarshaled.EventIdentifiers)
		require.Empty(t, unmarshaled.EventContent)
		require.NotNil(t, unmarshaled.Features.PullRequest)
		require.Empty(t, unmarshaled.Features.PullRequest.Labels)
	})

	t.Run("special characters in string fields", func(t *testing.T) {
		original := &NewJobAPIRequest{
			ProblemStatement: "Fix bug with \"quotes\" and 'apostrophes' and \nnewlines",
			RunName:          "run-with-special-chars-!@#$%",
			EventURL:         "https://example.com/path?param=value&other=123",
			Features: &EnvironmentFeatures{
				PullRequest: &PullRequestFeature{
					Title:           "PR with emoji 🚀 and unicode ñ",
					BodyPlaceholder: "Body with\ttabs and\nnewlines",
					BodySuffix:      "Fixes #123\nCloses #456",
				},
			},
		}

		jsonData, err := json.Marshal(original)
		require.NoError(t, err)

		var unmarshaled NewJobAPIRequest
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		require.Equal(t, original.ProblemStatement, unmarshaled.ProblemStatement)
		require.Equal(t, original.RunName, unmarshaled.RunName)
		require.Equal(t, original.EventURL, unmarshaled.EventURL)
		require.Equal(t, original.Features.PullRequest.Title, unmarshaled.Features.PullRequest.Title)
		require.Equal(t, original.Features.PullRequest.BodyPlaceholder, unmarshaled.Features.PullRequest.BodyPlaceholder)
		require.Equal(t, original.Features.PullRequest.BodySuffix, unmarshaled.Features.PullRequest.BodySuffix)
	})

	t.Run("custom agent name", func(t *testing.T) {
		original := &NewJobAPIRequest{
			ProblemStatement: "Test both custom agent fields",
			CustomAgent:      "predefined-agent",
		}

		jsonData, err := json.Marshal(original)
		require.NoError(t, err)

		var unmarshaled NewJobAPIRequest
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		require.Equal(t, "predefined-agent", unmarshaled.CustomAgent)
	})
}

func TestBranchFeature_MarshalUnmarshal(t *testing.T) {
	t.Run("all fields populated", func(t *testing.T) {
		original := &BranchFeature{
			Name:    "feature-branch",
			BaseRef: "develop",
		}

		jsonData, err := json.Marshal(original)
		require.NoError(t, err)

		var unmarshaled BranchFeature
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		require.Equal(t, original.Name, unmarshaled.Name)
		require.Equal(t, original.BaseRef, unmarshaled.BaseRef)
	})

	t.Run("empty fields", func(t *testing.T) {
		original := &BranchFeature{}

		jsonData, err := json.Marshal(original)
		require.NoError(t, err)

		var unmarshaled BranchFeature
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		require.Empty(t, unmarshaled.Name)
		require.Empty(t, unmarshaled.BaseRef)
	})
}

func TestPullRequestFeature_MarshalUnmarshal(t *testing.T) {
	t.Run("all fields populated", func(t *testing.T) {
		original := &PullRequestFeature{
			Title:           "Test PR",
			BodyPlaceholder: "Test body",
			BodySuffix:      "Fixes #123",
			BaseRef:         "main",
			HeadRef:         "feature",
			Labels:          []string{"bug", "enhancement"},
		}

		jsonData, err := json.Marshal(original)
		require.NoError(t, err)

		var unmarshaled PullRequestFeature
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		require.Equal(t, original.Title, unmarshaled.Title)
		require.Equal(t, original.BodyPlaceholder, unmarshaled.BodyPlaceholder)
		require.Equal(t, original.BodySuffix, unmarshaled.BodySuffix)
		require.Equal(t, original.BaseRef, unmarshaled.BaseRef)
		require.Equal(t, original.HeadRef, unmarshaled.HeadRef)
		require.Equal(t, original.Labels, unmarshaled.Labels)
	})

	t.Run("empty fields and nil labels", func(t *testing.T) {
		original := &PullRequestFeature{}

		jsonData, err := json.Marshal(original)
		require.NoError(t, err)

		var unmarshaled PullRequestFeature
		err = json.Unmarshal(jsonData, &unmarshaled)
		require.NoError(t, err)

		require.Empty(t, unmarshaled.Title)
		require.Empty(t, unmarshaled.BodyPlaceholder)
		require.Empty(t, unmarshaled.BodySuffix)
		require.Empty(t, unmarshaled.BaseRef)
		require.Empty(t, unmarshaled.HeadRef)
		require.Nil(t, unmarshaled.Labels)
	})
}

func TestPRBodyCharacterLimits(t *testing.T) {
	t.Run("separator lengths are correctly accounted for", func(t *testing.T) {
		// Verify separator constants match actual lengths
		require.Equal(t, 42, len(jobservice.PullRequestBodyOriginalPromptSeparator), "PullRequestBodyOriginalPromptSeparator should be 42 chars")
		require.Equal(t, 46, len(jobservice.PullRequestBodySuffixSeparator), "PullRequestBodySuffixSeparator should be 46 chars")
	})

	t.Run("MaxCompiledPullRequestBodySuffixLength calculation is correct", func(t *testing.T) {
		// Calculate expected value manually
		expectedLength := len(jobservice.PullRequestBodyOriginalPromptSeparator) +
			jobservice.MaxPullRequestBodyProblemStatementQuoteLengthWithWrapper +
			jobservice.MaxCompiledPullRequestBodyAgentDetailsLength +
			len(jobservice.PullRequestBodySuffixSeparator) +
			jobservice.MaxPullRequestBodySuffixLength

		require.Equal(t, expectedLength, jobservice.MaxCompiledPullRequestBodySuffixLength,
			"MaxCompiledPullRequestBodySuffixLength should equal the sum of all its components")
	})

	t.Run("jobservice.MaxPullRequestBodyPlaceholderLength calculation is correct", func(t *testing.T) {
		// Calculate expected value manually
		expectedLength := github.MaxPullRequestBodyLength - jobservice.MaxCompiledPullRequestBodySuffixLength

		require.Equal(t, expectedLength, jobservice.MaxPullRequestBodyPlaceholderLength,
			"jobservice.MaxPullRequestBodyPlaceholderLength should be GitHub max minus compiled suffix length")
	})

	t.Run("total PR body does not exceed GitHub's limit", func(t *testing.T) {
		// Maximum possible PR body length
		maxPossibleLength := jobservice.MaxPullRequestBodyPlaceholderLength + jobservice.MaxCompiledPullRequestBodySuffixLength

		require.LessOrEqual(t, maxPossibleLength, github.MaxPullRequestBodyLength,
			"Maximum possible PR body length should not exceed GitHub's limit")

		// Verify it's exactly at the limit (we want to use all available space)
		require.Equal(t, github.MaxPullRequestBodyLength, maxPossibleLength,
			"Maximum possible PR body should exactly equal GitHub's limit")
	})

	t.Run("problem statement quote wrapper length is correct", func(t *testing.T) {
		// Calculate the actual wrapper length
		actualWrapperLength := len(jobservice.PullRequestBodyProblemStatementQuoteWrapper) - 2 // -2 for the %s placeholder

		// The wrapper should be approximately 70 chars (as documented)
		require.InDelta(t, 70, actualWrapperLength, 10,
			"jobservice.PullRequestBodyProblemStatementQuoteWrapper should be approximately 70 chars (±10)")
	})

	t.Run("jobservice.PullRequestBodyOriginalPromptSeparator calculation is correct", func(t *testing.T) {
		expectedLength := len(jobservice.PullRequestBodyProblemStatementQuoteWrapper) + jobservice.MaxPullRequestBodyProblemStatementQuoteLength

		require.Equal(t, expectedLength, jobservice.MaxPullRequestBodyProblemStatementQuoteLengthWithWrapper,
			"jobservice.PullRequestBodyOriginalPromptSeparator should equal wrapper + quote length")
	})

	t.Run("agent name wrapper length is correct", func(t *testing.T) {
		// Calculate the actual wrapper length
		actualWrapperLength := len(jobservice.PullRequestBodyAgentNameWrapper) - 2 // -2 for the %s placeholder

		// The wrapper should be approximately 31 chars (as documented in comment)
		require.InDelta(t, 31, actualWrapperLength, 5,
			"jobservice.PullRequestBodyAgentNameWrapper should be approximately 31 chars (±5)")
	})

	t.Run("jobservice.MaxPullRequestBodyAgentNameLengthWithWrapper calculation is correct", func(t *testing.T) {
		expectedLength := len(jobservice.PullRequestBodyAgentNameWrapper) + jobservice.MaxPullRequestBodyAgentNameLength

		require.Equal(t, expectedLength, jobservice.MaxPullRequestBodyAgentNameLengthWithWrapper,
			"jobservice.MaxPullRequestBodyAgentNameLengthWithWrapper should equal wrapper + name length")
	})

	t.Run("jobservice.MaxCompiledPullRequestBodyAgentDetailsLength calculation is correct", func(t *testing.T) {
		expectedLength := jobservice.MaxPullRequestBodyAgentNameLengthWithWrapper + jobservice.MaxPullRequestBodyAgentDescriptionLength

		require.Equal(t, expectedLength, jobservice.MaxCompiledPullRequestBodyAgentDetailsLength,
			"jobservice.MaxCompiledPullRequestBodyAgentDetailsLength should equal name with wrapper + description length")
	})

	t.Run("documented character allocation matches actual constants", func(t *testing.T) {
		actualBothSeparators := len(jobservice.PullRequestBodyOriginalPromptSeparator) + len(jobservice.PullRequestBodySuffixSeparator)
		require.Equal(t, 88, actualBothSeparators, "Both separators should total 88 chars")

		actualTotal := actualBothSeparators +
			jobservice.MaxPullRequestBodyProblemStatementQuoteLengthWithWrapper +
			jobservice.MaxCompiledPullRequestBodyAgentDetailsLength +
			jobservice.MaxPullRequestBodySuffixLength

		require.Equal(t, jobservice.MaxCompiledPullRequestBodySuffixLength, actualTotal,
			"Documented character allocation should match jobservice.MaxCompiledPullRequestBodySuffixLength")
	})
}

func stringPtr(s string) *string {
	return &s
}
