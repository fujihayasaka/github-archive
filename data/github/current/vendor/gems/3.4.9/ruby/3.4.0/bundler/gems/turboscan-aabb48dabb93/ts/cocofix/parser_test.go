package cocofix

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestParseResponseJsonSuccess(t *testing.T) {
	input := `[
		{
			"cocoFixVersion": "0.11.0",
			"alert": {
				"message": "Cross-site scripting vulnerability due to a user-provided value."
			},
			"outcome": {
				"kind": "fix",
				"diffs": [
					{
						"path": "foo.js",
						"diff": "some_diff"
					}
				],
				"assessment": {
					"outcome": "valid"
				},
				"details": {
					"fixDescription": "Fix xss injection"
				}
			}
		}
	]`
	res, err := parseResponseJson([]byte(input))
	require.NoError(t, err)
	require.Equal(t, 1, len(res))
	first := res[0]
	require.Equal(t, "fix", first.Outcome.Kind)
	require.Empty(t, first.Outcome.Error)
	require.Equal(t, "0.11.0", first.CoCoFixVersion)
	require.Equal(t, "Cross-site scripting vulnerability due to a user-provided value.", first.Alert.Message)
	require.Equal(t, "valid", first.Outcome.Assessment.Outcome)

	require.Equal(t, "Fix xss injection", first.Outcome.Details.FixDescription)
	diffs := first.Outcome.Diffs
	require.Equal(t, "foo.js", diffs[0].Path)
	require.Equal(t, "some_diff", diffs[0].Diff)
}

func TestParseResponseJsonProblems(t *testing.T) {
	input := `[
		{
			"cocoFixVersion": "0.11.0",
			"alert": {
				"message": "Cross-site scripting vulnerability due to a user-provided value."
			},
			"outcome": {
				"kind": "fix",
				"diffs": [],
				"assessment": {
					"outcome": "invalid",
					"problems": [{
						"kind": "no code changes",
						"description": "The fix did not change the code."
					}]
				},
				"details": {
					"fixDescription": "No idea how to fix this.",
					"dependencyMetadata": [
						{
							"name": "escape-html",
							"version": "1.0.3",
							"advisories": [],
							"url": "https://www.npmjs.com/package/escape-html"
						}
					]
				}
			}
		}
	]`
	res, err := parseResponseJson([]byte(input))
	require.NoError(t, err)
	require.Equal(t, 1, len(res))
	first := res[0]
	require.Equal(t, "fix", first.Outcome.Kind)
	require.Equal(t, "invalid", first.Outcome.Assessment.Outcome)
	problems := first.Outcome.Assessment.Problems
	require.Equal(t, 1, len(problems))
	require.Equal(t, ProblemKind_NO_CODE_CHANGES, problems[0].Kind)
	require.Equal(t, "The fix did not change the code.", problems[0].Description)
	require.Len(t, first.Outcome.Details.DependencyMetadata, 1)
	dep := first.Outcome.Details.DependencyMetadata[0]
	require.Equal(t, "escape-html", dep.Name)
}

func TestParseResponseJsonError(t *testing.T) {
	input := `[
		{
			"cocoFixVersion": "0.11.0",
			"alert": {
				"message": "Cross-site scripting vulnerability due to a user-provided value."
			},
			"outcome": {
				"kind": "error",
				"error": "something went wrong",
				"description": "some description",
				"transient": false,
				"severity": "high"
			}
		}
	]`
	res, err := parseResponseJson([]byte(input))
	require.NoError(t, err)
	require.Equal(t, 1, len(res))
	first := res[0]
	require.Equal(t, "error", first.Outcome.Kind)
	require.Equal(t, "something went wrong", first.Outcome.Error)
	require.Empty(t, first.Outcome.Diffs)
}

func TestParseOutcome(t *testing.T) {
	input := `[
		{
			"cocoFixVersion": "0.11.0",
			"alert": {
				"message": "Cross-site scripting vulnerability due to a user-provided value."
			},
			"outcome": {
				"kind": "error",
				"error": "something went wrong",
				"description": "some description",
				"transient": false,
				"severity": "high"
			}
		}
	]`
	res, err := parseResponseJson([]byte(input))
	require.NoError(t, err)
	require.Equal(t, 1, len(res))
	require.Equal(t, OutcomeSeverity_HIGH, res[0].Outcome.Severity)

	input = `[
		{
			"cocoFixVersion": "0.11.0",
			"outcome": {
				"kind": "error",
				"error": "something went wrong",
				"description": "some description",
				"transient": false,
				"severity": "invaliddd"
			}
		}
	]`
	res, err = parseResponseJson([]byte(input))
	require.NoError(t, err)
	require.Equal(t, 1, len(res))
}
