package cocofix

import (
	"context"
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/turboscan/ts"
)

func TestMapFixesToAlerts_KindFix_OutcomeValid(t *testing.T) {
	fixes := CocofixResponse{
		Output{
			Alert: respAlert{
				Message: "some xss happened",
				RuleId:  "js/reflected-xss",
				Location: Location{
					Path:        "foo/bar.js",
					StartLine:   1,
					StartColumn: 5,
					EndColumn:   10,
					EndLine:     1,
				},
			},
			Outcome: Outcome{
				Kind: "fix",
				Diffs: []Diff{
					{
						Path: "foo/bar.js",
						Diff: "some_diff"},
					{
						Path: "foo/bar.js",
						Diff: "other_diff"},
				},
				Assessment: Assessment{
					Outcome: "valid",
				},
				Details: Details{
					FixDescription: "fix description",
					DependencyMetadata: []DependencyMetadata{
						{
							Name:      "baz",
							Version:   "1.2.3",
							Ecosystem: "npm",
							Advisories: []Advisory{
								{
									Id:       "123",
									Severity: string(ts.SuggestedFixAdvisorySeverity_CRITICAL),
								},
							},
						},
					},
				},
				Error: "",
			},
		},
	}

	defaultRef := []byte("refs/heads/main")
	analysis := &ts.Analysis{ID: 1, RepositoryID: 1, SourceRepositoryID: 1, Ref: defaultRef}
	alertNo := uint32(1)
	pa := &ts.PhysicalAlert{
		ID:       ts.PhysicalAlertID(1),
		Analysis: analysis,
		LogicalAlert: &ts.LogicalAlert{
			ID:              ts.LogicalAlertID(1),
			Number:          alertNo,
			SarifIdentifier: "js/reflected-xss",
		},
		RepositoryID: ts.RepositoryEID(1),
	}

	var beef ts.Sha1Checksum
	copy(beef[:], []byte("beef"))

	c := &CocofixRunner{}
	res, err := c.buildGenerateFixResponse(context.Background(), fixes[0], pa.RepositoryID, map[string]ts.Sha1Checksum{"foo/bar.js": beef})
	require.NoError(t, err)
	sf := res.SuggestedFix
	require.NotEmpty(t, sf.Files)
	for _, file := range sf.Files {
		require.Equal(t, "foo/bar.js", file.FilePath)
		require.Equal(t, beef, file.FileChecksum)
	}
	require.Equal(t, "baz", sf.DependencyMetadata[0].Name)
	require.Equal(t, "1.2.3", sf.DependencyMetadata[0].Version)
	require.Equal(t, "npm", sf.DependencyMetadata[0].Ecosystem)
	require.Equal(t, "123", sf.DependencyMetadata[0].Advisories[0].Id)
	require.Equal(t, ts.SuggestedFixAdvisorySeverity_CRITICAL, sf.DependencyMetadata[0].Advisories[0].Severity)
	require.Equal(t, ts.SuggestedFixAlertStateValid, res.SuggestedFixAlertState)
}

func TestMapFixesToAlerts_KindError(t *testing.T) {
	fixes := CocofixResponse{
		Output{
			Alert: respAlert{
				RuleId: "js/some-injection",
				Location: Location{
					Path:        "hello/world.js",
					StartLine:   1,
					StartColumn: 4,
					EndColumn:   10,
					EndLine:     1,
				},
			},
			Outcome: Outcome{
				Kind:     "error",
				Error:    "something went wrong",
				Severity: OutcomeSeverity_LOW,
			},
		},
	}

	defaultRef := []byte("refs/heads/main")
	analysis := &ts.Analysis{ID: 1, RepositoryID: 1, SourceRepositoryID: 1, Ref: defaultRef}
	pa := &ts.PhysicalAlert{
		ID:       ts.PhysicalAlertID(2),
		Analysis: analysis,
		LogicalAlert: &ts.LogicalAlert{
			ID:              ts.LogicalAlertID(1),
			Number:          2,
			SarifIdentifier: "js/some-injection",
		},
		RepositoryID: ts.RepositoryEID(1),
	}

	var sum ts.Sha1Checksum
	copy(sum[:], []byte("beef"))
	c := &CocofixRunner{}
	res, err := c.buildGenerateFixResponse(context.Background(), fixes[0], pa.RepositoryID, nil)
	require.Error(t, err)
	require.Empty(t, res)
	require.True(t, IsNonRetriableError(err))
}

func TestMapFixesToAlerts_KindFix_OutcomeInvalid(t *testing.T) {
	fixes := CocofixResponse{
		Output{
			Alert: respAlert{
				RuleId: "js/some-injection",
				Location: Location{
					Path:        "hello/world.js",
					StartLine:   10,
					StartColumn: 4,
					EndColumn:   10,
					EndLine:     10,
				},
			},
			Outcome: Outcome{
				Kind: "fix",
				Assessment: Assessment{
					Outcome: "invalid",
				},
			},
		},
	}

	defaultRef := []byte("refs/heads/main")
	analysis := &ts.Analysis{ID: 1, RepositoryID: 1, SourceRepositoryID: 1, Ref: defaultRef}
	pa := &ts.PhysicalAlert{
		ID:       ts.PhysicalAlertID(3),
		Analysis: analysis,
		LogicalAlert: &ts.LogicalAlert{
			ID:              ts.LogicalAlertID(1),
			Number:          3,
			SarifIdentifier: "js/some-injection",
		},
		RepositoryID: ts.RepositoryEID(1),
	}

	var sum ts.Sha1Checksum
	copy(sum[:], []byte("beef"))
	c := &CocofixRunner{}
	res, err := c.buildGenerateFixResponse(context.Background(), fixes[0], pa.RepositoryID, nil)
	require.NoError(t, err)
	require.Nil(t, res.SuggestedFix)
	require.Equal(t, ts.SuggestedFixAlertStateInvalid, res.SuggestedFixAlertState)
}

func TestMapFixesToAlerts_KindError_SeverityCritical(t *testing.T) {
	fixes := CocofixResponse{
		Output{
			Alert: respAlert{
				RuleId: "js/some-injection",
				Location: Location{
					Path:        "hello/world.js",
					StartLine:   10,
					StartColumn: 4,
					EndColumn:   10,
					EndLine:     10,
				},
			},
			Outcome: Outcome{
				Kind:     "error",
				Severity: "critical",
			},
		},
	}

	defaultRef := []byte("refs/heads/main")
	analysis := &ts.Analysis{ID: 1, RepositoryID: 1, SourceRepositoryID: 1, Ref: defaultRef}
	pa := &ts.PhysicalAlert{
		ID:       ts.PhysicalAlertID(1),
		FilePath: "hello/world.js",
		Region: ts.Region{
			StartLine:   10,
			StartColumn: 4,
			EndColumn:   10,
			EndLine:     10,
		},
		Analysis: analysis,
		LogicalAlert: &ts.LogicalAlert{
			ID:              ts.LogicalAlertID(1),
			SarifIdentifier: "js/some-injection",
		},
	}

	c := &CocofixRunner{}
	res, err := c.buildGenerateFixResponse(context.Background(), fixes[0], pa.RepositoryID, nil)
	require.Error(t, err)
	require.Empty(t, res)
	require.True(t, IsNonRetriableError(err))
}

func TestMapFixesToAlerts_KindError_SeverityHigh(t *testing.T) {
	fixes := CocofixResponse{
		Output{
			Alert: respAlert{
				RuleId: "js/some-injection",
				Location: Location{
					Path:        "hello/world.js",
					StartLine:   10,
					StartColumn: 4,
					EndColumn:   10,
					EndLine:     10,
				},
			},
			Outcome: Outcome{
				Kind:     "error",
				Severity: "high",
			},
		},
	}

	defaultRef := []byte("refs/heads/main")
	analysis := &ts.Analysis{ID: 1, RepositoryID: 1, SourceRepositoryID: 1, Ref: defaultRef}
	pa := &ts.PhysicalAlert{
		ID:       ts.PhysicalAlertID(1),
		Analysis: analysis,
		LogicalAlert: &ts.LogicalAlert{
			ID:              ts.LogicalAlertID(1),
			SarifIdentifier: "js/some-injection",
		},
	}

	c := &CocofixRunner{}
	res, err := c.buildGenerateFixResponse(context.Background(), fixes[0], pa.RepositoryID, nil)
	require.Error(t, err)
	require.Empty(t, res)
	require.True(t, IsNonRetriableError(err))
}

func TestMapFixesToAlerts_KindError_Transient(t *testing.T) {
	fixes := CocofixResponse{
		Output{
			Alert: respAlert{
				RuleId: "js/some-injection",
				Location: Location{
					Path:        "hello/world.js",
					StartLine:   10,
					StartColumn: 4,
					EndColumn:   10,
					EndLine:     10,
				},
			},
			Outcome: Outcome{
				Kind:      "error",
				Transient: true,
				Severity:  "low",
			},
		},
	}

	defaultRef := []byte("refs/heads/main")
	analysis := &ts.Analysis{ID: 1, RepositoryID: 1, SourceRepositoryID: 1, Ref: defaultRef}
	pa := &ts.PhysicalAlert{
		ID:       ts.PhysicalAlertID(1),
		Analysis: analysis,
		LogicalAlert: &ts.LogicalAlert{
			ID:              ts.LogicalAlertID(1),
			SarifIdentifier: "js/some-injection",
		},
	}

	c := &CocofixRunner{}
	res, err := c.buildGenerateFixResponse(context.Background(), fixes[0], pa.RepositoryID, nil)
	require.Error(t, err)
	require.Empty(t, res)
	require.True(t, IsTransientError(err))
}
