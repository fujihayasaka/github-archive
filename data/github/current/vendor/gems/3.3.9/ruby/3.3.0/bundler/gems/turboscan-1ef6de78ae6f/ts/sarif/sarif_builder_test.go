package sarif

import (
	"encoding/json"
	"flag"
	"os"
	"path/filepath"
	"regexp"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	v210 "github.com/github/turboscan/ts/sarif/v2_1_0_turboscan"

	"github.com/stretchr/testify/require"
)

func createAnalysis() *ts.Analysis {
	repoID := ts.RepositoryEID(1)

	tool := &ts.Tool{
		ID:             1,
		CanonicalName:  "CodeQL",
		GUID:           "e91e0de1-9ce6-4ed3-83ec-16bb54c8000a",
		IsInternalGUID: false,
	}

	toolVersion := &ts.ToolVersion{
		ID:              1,
		Version:         "1.2.3",
		SemanticVersion: "1.2.3",
		Name:            "CodeQL",
	}
	extensionVersion := &ts.ToolVersion{
		ID:              2,
		SemanticVersion: "1.0.0",
		Name:            "Query Pack - A",
	}

	ss1 := 7.6
	rule1 := &ts.Rule{
		ID:               1,
		SarifIdentifier:  "Rule/1",
		Name:             "Rule1",
		ShortDescription: "Rule 1",
		FullDescription:  "This is Rule 1",
		SeverityLevel:    ts.SeverityLevelError,
		SecuritySeverity: &ss1,
		Tags:             []ts.RuleTag{{Tag: "Tag1"}, {Tag: "Tag2"}},
	}

	rule2 := &ts.Rule{
		DefiningToolVersionID: 2,
		ID:                    2,
		SarifIdentifier:       "Rule/2",
		Name:                  "Rule2",
		ShortDescription:      "",
		FullDescription:       "",
		SeverityLevel:         ts.SeverityLevelError,
		Tags:                  []ts.RuleTag{},
		Help:                  "I am helpful",
	}

	alerts := make([]*ts.PhysicalAlert, 0, 3)

	now := sqltime.Now()
	tflMessage := "tflMessage"
	p1 := ts.PhysicalAlert{
		ID:                  1,
		RuleID:              rule1.ID,
		RuleSarifIdentifier: rule1.SarifIdentifier,
		SeverityLevel:       rule1.SeverityLevel,
		SecuritySeverity:    &ss1,
		Fingerprint:         "fp1",
		Message:             "message",
		MessageMarkdown:     "**message**",
		FilePath:            "file1",
		LastStateChangeAt:   now,
		Region: ts.Region{
			StartLine:   1,
			EndLine:     2,
			StartColumn: 1,
			EndColumn:   2,
		},
		Snippet: &ts.Snippet{
			Region: ts.Region{
				StartLine:   1,
				EndLine:     2,
				StartColumn: 1,
				EndColumn:   2,
			},
			Text: "snippet1",
		},
		// 2 CodeFlows: 1 with 2 ThreadFlows and 1 with 1 ThreadFlow
		CodeFlowsDocument: &ts.CodeFlowsDocument{
			RepositoryID: repoID,
			// CodeFlow 1 with 2 ThreadFlows
			Document: ts.SortCodeFlows(ts.CodeFlows{
				ts.CodeFlow{
					CodeFlowIndex:   1,
					ThreadFlowIndex: 1,
					StepIndex:       1,
					Message:         &tflMessage,
					FilePath:        "file1",
					Region: ts.Region{
						StartLine:   1,
						EndLine:     2,
						StartColumn: 1,
						EndColumn:   2,
					},
				},

				ts.CodeFlow{
					CodeFlowIndex:   1,
					ThreadFlowIndex: 1,
					StepIndex:       2,
					Message:         &tflMessage,
					FilePath:        "file2",
					Region: ts.Region{
						StartLine:   1,
						EndLine:     2,
						StartColumn: 1,
						EndColumn:   2,
					},
				},
				ts.CodeFlow{
					CodeFlowIndex:   1,
					ThreadFlowIndex: 2,
					StepIndex:       1,
					Message:         &tflMessage,
					FilePath:        "file1",
					Region: ts.Region{
						StartLine:   2,
						EndLine:     2,
						StartColumn: 2,
						EndColumn:   2,
					},
				},
				// CodeFlow 2 with 1 ThreadFlow
				ts.CodeFlow{
					CodeFlowIndex:   2,
					ThreadFlowIndex: 1,
					StepIndex:       2,
					Message:         &tflMessage,
					FilePath:        "file3",
					Region: ts.Region{
						StartLine:   1,
						EndLine:     2,
						StartColumn: 1,
						EndColumn:   2,
					},
				},
				ts.CodeFlow{
					CodeFlowIndex:   2,
					ThreadFlowIndex: 1,
					StepIndex:       1,
					Message:         &tflMessage,
					FilePath:        "file4",
					Region: ts.Region{
						StartLine:   1,
						EndLine:     2,
						StartColumn: 1,
						EndColumn:   2,
					},
				},
			}),
		},
		LogicalAlert: &ts.LogicalAlert{
			Number: 1,
			RuleID: rule1.ID,
			Rule:   rule1,
		},
		RelatedLocations: []*ts.RelatedLocation{
			{
				RepositoryID: repoID,
				FilePath:     "file1",
				Region: ts.Region{
					StartLine:   3,
					EndLine:     4,
					StartColumn: 3,
					EndColumn:   4,
				},
				Message:          "Related location message",
				ReplacementIndex: 1,
			},
		},
	}
	alerts = append(alerts, &p1)

	ss2 := 10.0
	guid := "a5c8153a-0cd3-4685-85fd-efc16ab03c7e"
	p2 := ts.PhysicalAlert{
		RuleID:              rule1.ID,
		GUID:                &guid,
		RuleSarifIdentifier: rule1.SarifIdentifier,
		SeverityLevel:       rule1.SeverityLevel,
		SecuritySeverity:    &ss2,
		Fingerprint:         "fp2",
		Message:             "message",
		MessageMarkdown:     "**message**",
		FilePath:            "file2",
		LastStateChangeAt:   now,
		Region: ts.Region{
			StartLine:   1,
			EndLine:     2,
			StartColumn: 1,
			EndColumn:   2,
		},
		Snippet: &ts.Snippet{
			Region: ts.Region{
				StartLine:   1,
				EndLine:     2,
				StartColumn: 1,
				EndColumn:   2,
			},
			Text: "snippet2",
		},
		LogicalAlert: &ts.LogicalAlert{
			Number: 2,
			RuleID: rule1.ID,
			Rule:   rule1,
		},
	}
	alerts = append(alerts, &p2)

	p3 := ts.PhysicalAlert{
		RuleID:              rule2.ID,
		RuleSarifIdentifier: rule2.SarifIdentifier,
		SeverityLevel:       rule2.SeverityLevel,
		Fingerprint:         "fp3",
		Message:             "message",
		MessageMarkdown:     "**message**",
		FilePath:            "file1",
		LastStateChangeAt:   now,
		Region: ts.Region{
			StartLine:   3,
			EndLine:     4,
			StartColumn: 3,
			EndColumn:   4,
		},
		Snippet: &ts.Snippet{
			Region: ts.Region{
				StartLine:   3,
				EndLine:     4,
				StartColumn: 3,
				EndColumn:   4,
			},
			Text: "snippet3",
		},
		LogicalAlert: &ts.LogicalAlert{
			Number: 3,
			RuleID: rule2.ID,
			Rule:   rule2,
		},
	}
	alerts = append(alerts, &p3)

	analysis := &ts.Analysis{
		ToolVersionID:      toolVersion.ID,
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/master"),
		CommitOid:          "da39a3ee5e6b4b0d3255bfef95601890afd80709",
		AnalysisName:       "CodeQL Analysis",
		ToolID:             tool.ID,
		Tool:               tool,
		ToolVersion:        toolVersion,
		PhysicalAlerts:     alerts,
		Rules: map[string]*ts.Rule{
			rule1.SarifIdentifier: rule1,
			rule2.SarifIdentifier: rule2,
		},
		ToolVersions: []*ts.ToolVersion{toolVersion, extensionVersion},
	}
	for _, a := range analysis.PhysicalAlerts {
		a.Analysis = analysis
	}

	return analysis
}

func TestInternalBuildSarif(t *testing.T) {
	analysis := createAnalysis()

	sarif, err := buildSarif(analysis, BuildSarifOpts{})
	require.NoError(t, err)
	require.Equal(t, 3, len(sarif.Runs[0].Results))                  // 3 results
	require.Equal(t, 1, len(sarif.Runs[0].Tool.Driver.Rules))        // 1 rule
	require.Equal(t, 1, len(sarif.Runs[0].Tool.Extensions[0].Rules)) // 1 rule
	require.Equal(t, 4, len(sarif.Runs[0].Artifacts))                // 4 artifacts

	for _, r := range sarif.Runs[0].Results {
		artifactLocation := r.Locations[0].PhysicalLocation.ArtifactLocation
		require.Equal(t, sarif.Runs[0].Artifacts[artifactLocation.Index].Location.Uri, artifactLocation.Uri)
	}
}

var rebuild = flag.Bool("rebuild", false, "Rebuild and overwrite existing ts/sarif/testdata/builtSarif.sarif")

func TestBuildSarif(t *testing.T) {
	analysis := createAnalysis()
	opts := BuildSarifOpts{
		RepoHTMLURL: "https://github.com/github/turboscan",
		AlertAPIURL: "https://api.github.com/repos/github/turboscan/code-scanning/alerts",
		Indent:      true,
	}

	sarif, err := BuildSarif(analysis, opts)
	require.NoError(t, err)

	testDataPath := filepath.Join("testdata", "builtSarif.sarif")

	if *rebuild {
		require.NoError(t, os.WriteFile(testDataPath, []byte(sarif), 0o644))
		return
	}

	f, err := os.ReadFile(testDataPath)
	require.NoError(t, err)
	require.Equal(t, string(f), sarif, "generated SARIF has changed: run make ts/sarif/testdata/builtSarif.sarif if this change looks legitimate.")

	var e v210.SARIF210ForGitHubCodeScanning
	err = json.Unmarshal([]byte(sarif), &e)
	require.NoError(t, err)
}

func TestBuildSarifWithoutIndent(t *testing.T) {
	analysis := createAnalysis()
	opts := BuildSarifOpts{
		RepoHTMLURL: "https://github.com/github/turboscan",
		AlertAPIURL: "https://api.github.com/repos/github/turboscan/code-scanning/alerts",
	}

	sarif, err := BuildSarif(analysis, opts)
	require.NoError(t, err)

	require.NotRegexp(t, regexp.MustCompile(`\n\s+`), sarif)
}
