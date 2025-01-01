package archiver

import (
	"bytes"
	"context"
	"os"
	"testing"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/sarif/store"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
)

func NewArchiverService(db *gorm.DB) *Service {
	return NewService(db, store.TestMemoryStore())
}

func TestGetAnalysisWithAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	s := NewArchiverService(db)

	repoID := ts.RepositoryEID(1)

	tool := &ts.Tool{
		CanonicalName:  "CodeQL",
		GUID:           "e91e0de1-9ce6-4ed3-83ec-16bb54c8000a",
		IsInternalGUID: false,
	}
	dbtest.RequireCreate(t, db, tool)

	toolVersion := &ts.ToolVersion{
		Version: "1.2.3",
	}
	dbtest.RequireCreate(t, db, toolVersion)

	incompleteAnalysis := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/master"),
		CommitOid:          "da39a3ee5e6b4b0d3255bfef95601890afd80709",
		ToolID:             tool.ID,
		ToolVersionID:      toolVersion.ID,
	}
	dbtest.RequireCreate(t, db, incompleteAnalysis)

	analysis := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/master"),
		CommitOid:          "da39a3ee5e6b4b0d3255bfef95601890afd80709",
		ToolID:             tool.ID,
		ToolVersionID:      toolVersion.ID,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, analysis)

	rule1 := &ts.Rule{
		Name:             "Rule1",
		ShortDescription: "Rule 1",
		FullDescription:  "This is Rule 1",
		SeverityLevel:    ts.SeverityLevelError,
	}
	rule1.SetTags([]string{"rule1"})
	dbtest.RequireCreate(t, db, rule1)

	rule2 := &ts.Rule{
		SarifIdentifier:  "Rule/2",
		Name:             "Rule2",
		ShortDescription: "Rule 2",
		FullDescription:  "This is Rule 2",
		SeverityLevel:    ts.SeverityLevelError,
	}
	rule2.SetTags([]string{"rule2"})
	dbtest.RequireCreate(t, db, rule2)

	s1 := &ts.Snippet{
		Region: ts.Region{
			StartLine:   1,
			EndLine:     2,
			StartColumn: 1,
			EndColumn:   2,
		},
		Text: "snippet1",
		Hash: []byte{1},
	}
	dbtest.RequireCreate(t, db, s1)

	a1 := &ts.LogicalAlert{
		RuleID:                rule1.ID,
		Number:                1,
		StableAlertIdentifier: []byte{1},
	}
	dbtest.RequireCreate(t, db, a1)

	// 2 CodeFlows: 1 with 2 ThreadFlows and 1 with 1 ThreadFlow
	tflMessage := "tflMessage"
	doc := &ts.CodeFlowsDocument{
		RepositoryID: repoID,
		Document: ts.CodeFlows{
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
			}, ts.CodeFlow{
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
			}, ts.CodeFlow{
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
			}, ts.CodeFlow{
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
		},
	}

	dbtest.RequireCreate(t, db, doc)

	now := sqltime.Now()
	p1 := &ts.PhysicalAlert{
		RuleSarifIdentifier: rule1.SarifIdentifier,
		SeverityLevel:       rule1.SeverityLevel,
		Fingerprint:         "fp1",
		Message:             "message",
		MessageMarkdown:     "**message**",
		FilePath:            "src/file1",
		Region: ts.Region{
			StartLine:   1,
			EndLine:     2,
			StartColumn: 1,
			EndColumn:   2,
		},
		SnippetID:             &s1.ID,
		LogicalAlertID:        a1.ID,
		StableAlertIdentifier: []byte{1},
		AnalysisID:            analysis.ID,
		RepositoryID:          repoID,
		CodeFlowsDocumentID:   &doc.ID,
		LastStateChangeAt:     now,
	}
	dbtest.RequireCreate(t, db, p1)

	dbtest.RequireCreate(t, db, &ts.RelatedLocation{
		RepositoryID: repoID,
		FilePath:     "src/file2",
		Region: ts.Region{
			StartLine:   1,
			EndLine:     2,
			StartColumn: 1,
			EndColumn:   2,
		},
		Message:          "related location",
		ReplacementIndex: 1,
		PhysicalAlertID:  p1.ID,
	})

	s2 := &ts.Snippet{
		Region: ts.Region{
			StartLine:   1,
			EndLine:     2,
			StartColumn: 1,
			EndColumn:   2,
		},
		Text: "snippet2",
		Hash: []byte{2},
	}
	dbtest.RequireCreate(t, db, s2)

	a2 := &ts.LogicalAlert{
		RuleID:                rule1.ID,
		Number:                2,
		StableAlertIdentifier: []byte{2},
	}
	dbtest.RequireCreate(t, db, a2)

	p2 := &ts.PhysicalAlert{
		RuleSarifIdentifier: rule1.SarifIdentifier,
		SeverityLevel:       rule1.SeverityLevel,
		Fingerprint:         "fp2",
		Message:             "message",
		MessageMarkdown:     "**message**",
		FilePath:            "src/file2",
		Region: ts.Region{
			StartLine:   1,
			EndLine:     2,
			StartColumn: 1,
			EndColumn:   2,
		},
		SnippetID:             &s2.ID,
		LogicalAlertID:        a2.ID,
		StableAlertIdentifier: []byte{2},
		AnalysisID:            analysis.ID,
		RepositoryID:          repoID,
		LastStateChangeAt:     now,
	}
	dbtest.RequireCreate(t, db, p2)

	s3 := &ts.Snippet{
		Region: ts.Region{
			StartLine:   3,
			EndLine:     4,
			StartColumn: 3,
			EndColumn:   4,
		},
		Text: "snippet3",
		Hash: []byte{3},
	}
	dbtest.RequireCreate(t, db, s3)

	a3 := &ts.LogicalAlert{
		RuleID:                rule2.ID,
		Number:                3,
		StableAlertIdentifier: []byte{3},
	}
	dbtest.RequireCreate(t, db, a3)

	p3 := &ts.PhysicalAlert{
		RuleSarifIdentifier: rule2.SarifIdentifier,
		SeverityLevel:       rule2.SeverityLevel,
		Fingerprint:         "fp3",
		Message:             "message",
		MessageMarkdown:     "**message**",
		FilePath:            "src/file1",
		Region: ts.Region{
			StartLine:   3,
			EndLine:     4,
			StartColumn: 3,
			EndColumn:   4,
		},
		SnippetID:             &s3.ID,
		LogicalAlertID:        a3.ID,
		StableAlertIdentifier: []byte{3},
		AnalysisID:            analysis.ID,
		RepositoryID:          repoID,
		LastStateChangeAt:     now,
	}
	dbtest.RequireCreate(t, db, p3)

	_, err := s.getAnalysisWithAlerts(ctx, repoID, incompleteAnalysis.ID, false)
	require.Error(t, err, ts.ErrAnalysisNotFound)
	a, err := s.getAnalysisWithAlerts(ctx, repoID, incompleteAnalysis.ID, true)
	require.NoError(t, err)
	require.Equal(t, incompleteAnalysis.ID, a.ID)

	a, err = s.getAnalysisWithAlerts(ctx, repoID, analysis.ID, false)
	require.NoError(t, err)
	require.Equal(t, tool.ID, a.Tool.ID)
	require.Equal(t, toolVersion.ID, a.ToolVersion.ID)
	require.Equal(t, 3, len(a.PhysicalAlerts))
	require.NotNil(t, a.PhysicalAlerts[0].CodeFlowsDocument)
	require.Equal(t, 5, len(a.PhysicalAlerts[0].CodeFlowsDocument.Document))
	require.Equal(t, 1, len(a.PhysicalAlerts[0].RelatedLocations))
	require.NotNil(t, a.PhysicalAlerts[2].LogicalAlert)
	require.Equal(t, a3.Number, a.PhysicalAlerts[2].LogicalAlert.Number)
	require.NotNil(t, a.PhysicalAlerts[2].LogicalAlert.Rule)
	require.Equal(t, true, a.PhysicalAlerts[2].LogicalAlert.Rule.HasTag(rule2.Tags[0].Tag))

	_, err = s.getAnalysisWithAlerts(ctx, repoID, analysis.ID+1, false)
	require.Equal(t, err, ts.ErrAnalysisNotFound)
	_, err = s.getAnalysisWithAlerts(ctx, repoID, analysis.ID+1, true)
	require.Equal(t, err, ts.ErrAnalysisNotFound)
}

func TestExtractCodePaths(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	sarifStore := store.TestMemoryStore()
	require.NoError(t, sarifStore.Open(ctx))
	s := NewService(db, sarifStore)

	sarifPath := "../../sarif/testdata/builtSarif.sarif"
	data, err := os.ReadFile(sarifPath)
	require.NoError(t, err)
	err = sarifStore.Upload(ctx, bytes.NewReader(data), sarifPath)
	require.NoError(t, err)

	repoID := ts.RepositoryEID(1)
	analysis := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/main"),
		AnalysisComplete:   true,
		ArchivalDataUrl:    sarifPath,
	}
	dbtest.RequireCreate(t, db, analysis)
	alerts := []*ts.LogicalAlert{
		{
			Number:       1,
			ID:           1,
			RepositoryID: repoID,
		},
	}
	cfMap, locMap, err := s.ExtractCodePaths(ctx, analysis, alerts)
	require.NoError(t, err)
	require.Equal(t, 1, len(cfMap))
	codeflows := cfMap[1]
	require.Equal(t, 5, len(codeflows.Document))
	message := codeflows.Document[0].Message
	require.Equal(t, "tflMessage", *message)
	require.Equal(t, 1, len(locMap))
	relatedLocations := locMap[1]
	require.Equal(t, 1, len(relatedLocations))
	require.Equal(t, "Related location message", relatedLocations[0].Message)
}

func TestExtractCodePaths_NoResult(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	sarifStore := store.TestMemoryStore()
	require.NoError(t, sarifStore.Open(ctx))
	s := NewService(db, sarifStore)

	sarifPath := "../../sarif/testdata/example.sarif"
	data, err := os.ReadFile(sarifPath)
	require.NoError(t, err)
	err = sarifStore.Upload(ctx, bytes.NewReader(data), sarifPath)
	require.NoError(t, err)

	repoID := ts.RepositoryEID(1)
	analysis := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/main"),
		AnalysisComplete:   true,
		ArchivalDataUrl:    sarifPath,
	}
	dbtest.RequireCreate(t, db, analysis)
	alerts := []*ts.LogicalAlert{
		{
			Number:       1,
			ID:           1,
			RepositoryID: repoID,
		},
	}
	_, _, err = s.ExtractCodePaths(ctx, analysis, alerts)
	require.Error(t, err, "result not found")
}

func TestExtractCodePaths_NoCodeFlows(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	sarifStore := store.TestMemoryStore()
	require.NoError(t, sarifStore.Open(ctx))
	s := NewService(db, sarifStore)

	sarifPath := "../../sarif/testdata/example-processed.sarif"
	data, err := os.ReadFile(sarifPath)
	require.NoError(t, err)
	err = sarifStore.Upload(ctx, bytes.NewReader(data), sarifPath)
	require.NoError(t, err)

	repoID := ts.RepositoryEID(1)
	analysis := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/main"),
		AnalysisComplete:   true,
		ArchivalDataUrl:    sarifPath,
	}
	dbtest.RequireCreate(t, db, analysis)
	alerts := []*ts.LogicalAlert{
		{
			Number:       1,
			ID:           1,
			RepositoryID: repoID,
		},
	}
	cfMap, _, err := s.ExtractCodePaths(ctx, analysis, alerts)
	require.NoError(t, err)
	require.Equal(t, 1, len(cfMap))
	// a result was found, but it had no codeflows
	require.Nil(t, cfMap[1])
}

func TestExtractCodePaths_FromDB(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	s := NewService(db, store.TestMemoryStore())

	repoID := ts.RepositoryEID(1)
	analysis := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/main"),
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, analysis)
	alerts := []*ts.LogicalAlert{
		{
			Number:       1,
			ID:           1,
			RepositoryID: repoID,
		},
	}
	_, _, err := s.ExtractCodePaths(ctx, analysis, alerts)
	// We expect an error from MySQL since we there are no alerts in the db
	require.Error(t, err, gorm.ErrRecordNotFound)
}

func TestExtractPhysicalAlertsByLocation(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	sarifStore := store.TestMemoryStore()
	require.NoError(t, sarifStore.Open(ctx))
	s := NewService(db, sarifStore)

	sarifPath := "../../sarif/testdata/builtSarif.sarif"
	data, err := os.ReadFile(sarifPath)
	require.NoError(t, err)
	err = sarifStore.Upload(ctx, bytes.NewReader(data), sarifPath)
	require.NoError(t, err)

	repoID := ts.RepositoryEID(1)
	analysis := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/main"),
		AnalysisComplete:   true,
		ArchivalDataUrl:    sarifPath,
	}
	dbtest.RequireCreate(t, db, analysis)
	existingChanges := map[string][]*proto.Change{
		"file1": {
			{
				StartLine: 1,
				EndLine:   1,
			},
		},
	}
	physicalAlerts, err := s.ExtractPhysicalAlertsByLocation(ctx, analysis, existingChanges)
	require.NoError(t, err)
	require.Equal(t, 1, len(physicalAlerts))
}
