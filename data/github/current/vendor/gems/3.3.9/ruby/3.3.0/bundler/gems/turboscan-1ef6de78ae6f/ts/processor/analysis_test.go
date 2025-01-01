package processor

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/analysismessage"
	"github.com/github/turboscan/ts/mysql/tool"

	"github.com/github/turboscan/ts/mysql/analysis"

	"github.com/SamuelTissot/sqltime"
	"github.com/aws/smithy-go/ptr"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/gormext"
	"github.com/github/turboscan/ts/sarif/samples"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
)

var defaultLatestAnalysisFilter = ts.LatestAnalysisFilter{
	Ref: []byte("refs/head/master"),
}

func testAnalysis(db *gorm.DB, repositoryID ts.RepositoryEID, commitOid string, ref string,
	analysisName string, tool *ts.Tool, environment map[string]string, startTime *sqltime.Time) *ts.Analysis {

	a := &ts.Analysis{
		RepositoryID:       repositoryID,
		SourceRepositoryID: repositoryID,
		Ref:                []byte(ref),
		CommitOid:          ts.ToSha(commitOid),
		AnalysisName:       ts.ToAnalysisName(analysisName),
		ToolID:             tool.ID,
		Tool:               tool,
		Environment:        environment,
		MostRecent:         false, // this isn't 'live' yet
		AnalysisComplete:   false, // will be set to complete in a transaction later
		BuildStartedAt:     startTime,
	}

	return a
}

func TestUpdateMostRecentAnalyses(t *testing.T) {
	db := dbtest.RequireConnection(t)

	s := analysis.NewService(db)
	ctx := context.Background()

	var a *ts.Analysis
	var arr []*ts.Analysis

	codeQL := &ts.Tool{CanonicalName: "CodeQL", GUID: "aaa"}
	notCodeQL := &ts.Tool{CanonicalName: "Not CodeQL", GUID: "bbb"}
	dbtest.RequireCreate(t, db, codeQL)
	dbtest.RequireCreate(t, db, notCodeQL)

	startTime := sqltime.Date(2017, time.February, 16, 0, 0, 0, 0, time.UTC)
	a = testAnalysis(db, ts.RepositoryEID(64), "deadbeef", "main", "analysis1", codeQL, map[string]string{}, &startTime)
	err := s.CreateAnalysis(ctx, a)
	require.NoError(t, err)
	err = s.CommitAnalysis(ctx, a)
	require.NoError(t, err)

	db.Find(&arr)
	require.Equal(t, 1, len(arr))
	require.True(t, arr[0].MostRecent)
	require.NotEmpty(t, arr[0].ConfigurationHashBytes)

	// now send a more recent analysis, and check that it gets set as most recent
	startTime = sqltime.Date(2018, time.February, 16, 0, 0, 0, 0, time.UTC)
	a1 := testAnalysis(db, ts.RepositoryEID(64), "deadbee2", "main", "analysis1", codeQL, map[string]string{},
		&startTime)
	a2 := testAnalysis(db, ts.RepositoryEID(64), "deadbee2", "main", "analysis2", notCodeQL, map[string]string{},
		&startTime)

	err = s.CreateAnalysis(ctx, a1)
	require.NoError(t, err)
	err = s.CreateAnalysis(ctx, a2)
	require.NoError(t, err)

	err = s.CommitAnalysis(ctx, a1)
	require.NoError(t, err)
	err = s.CommitAnalysis(ctx, a2)
	require.NoError(t, err)

	db.Find(&arr)
	require.Equal(t, 3, len(arr))
	require.False(t, arr[0].MostRecent)
	require.True(t, arr[1].MostRecent)
	require.True(t, arr[2].MostRecent)

	// Try to update, however use an old baseline
	a3 := testAnalysis(db, ts.RepositoryEID(64), "deadbee3", "main", "analysis1", codeQL, map[string]string{},
		&startTime)
	err = s.CreateAnalysis(ctx, a3)
	require.NoError(t, err)
	// Set the older baseline
	a3.BaselineID = &a.ID
	a3.MostRecent = false

	err = s.CommitAnalysis(ctx, a3)
	// Should allow, but not update the baseline
	require.NoError(t, err)

	// a1 should still be the latest baseline
	var a1d ts.Analysis
	require.NoError(t, db.Where("id = ?", a1.ID).First(&a1d).Error)
	require.True(t, a1d.MostRecent)
}

func TestSaveCounters(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()

	s := analysis.NewService(db)

	// Repo 1
	a1 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		AnalysisComplete:   true,
		MostRecent:         false,
		CommitOid:          "XXX",
		Ref:                []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, a1)

	a1.RulesCount = 1
	a1.ResultsCount = 1
	err := s.CommitAnalysis(ctx, a1)
	require.NoError(t, err)

	var a2 ts.Analysis
	require.NoError(t, db.Where("id = ?", a1.ID).First(&a2).Error)
	require.Equal(t, a1.RulesCount, a2.RulesCount)
	require.Equal(t, a1.ResultsCount, a2.ResultsCount)
}

func TestLatestAnalysesForRef(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()

	s := alert.TestService(db)
	toolS := tool.NewService(db, limits.TestLimitSelector())

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

	extensionA := ts.ToolFromCanonicalName("Query Pack A")
	dbtest.RequireCreate(t, db, extensionA)

	extensionB := ts.ToolFromCanonicalName("Query Pack B")
	dbtest.RequireCreate(t, db, extensionB)

	extensionC := ts.ToolFromCanonicalName("Query Pack C")
	dbtest.RequireCreate(t, db, extensionC)

	extensionAToolVersion := &ts.ToolVersion{
		ToolID:  extensionA.ID,
		Name:    extensionA.CanonicalName,
		Version: "1.0.0",
	}
	dbtest.RequireCreate(t, db, extensionAToolVersion)

	extensionBToolVersion := &ts.ToolVersion{
		ToolID:  extensionB.ID,
		Name:    extensionB.CanonicalName,
		Version: "1.0.0",
	}
	dbtest.RequireCreate(t, db, extensionBToolVersion)

	extensionCToolVersion := &ts.ToolVersion{
		ToolID:  extensionC.ID,
		Name:    extensionC.CanonicalName,
		Version: "1.0.0",
	}
	dbtest.RequireCreate(t, db, extensionCToolVersion)

	ruleA := &ts.Rule{SarifIdentifier: "a/test"}
	dbtest.RequireCreate(t, db, ruleA)

	ruleB := &ts.Rule{SarifIdentifier: "b/test"}
	dbtest.RequireCreate(t, db, ruleB)

	then := gormext.ConvertTime(ptr.Time(time.Now().Add(10 * 24 * time.Hour * -1)))

	analysis1 := &ts.Analysis{
		BaseModel: ts.BaseModel{
			CreatedAt: *then,
		},
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/master"),
		CommitOid:          "da39a3ee5e6b4b0d3255bfef95601890afd80709",
		Tool:               tool,
		ToolID:             tool.ID,
		ToolVersionID:      toolVersion.ID,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, analysis1)

	analysis2 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/master"),
		CommitOid:          "da39a3ee5e6b4b0d3255bfef95601890afd80709",
		Tool:               tool,
		ToolID:             tool.ID,
		ToolVersionID:      toolVersion.ID,
		AnalysisComplete:   true,
		MostRecent:         true,
	}
	dbtest.RequireCreate(t, db, analysis2)

	doc := samples.RequireSARIF(t, "./testdata/toolExecutionNotifications.sarif")
	ams := analysismessage.NewService(db)
	err := toolS.CreateAnalysisExtractedFiles(ctx, analysis1, doc.Runs[0], ams)
	require.NoError(t, err)

	err = toolS.CreateAnalysisExtractedFiles(ctx, analysis2, doc.Runs[0], ams)
	require.NoError(t, err)

	analyses, err := s.LatestAnalysesForRef(ctx, repoID, defaultLatestAnalysisFilter, false)
	require.NoError(t, err)
	require.Len(t, analyses, 1)
	require.NotNil(t, analyses[0].MinCreatedAt)
	require.Equal(t, analyses[0].ID, analysis2.ID)
	require.Equal(t, then, analyses[0].MinCreatedAt)

	analyses, err = s.LatestAnalysesForRef(ctx, repoID, ts.LatestAnalysisFilter{
		Ref: []byte("refs/head/master"), AnalysisIDs: []ts.AnalysisID{analysis1.ID},
	}, false)
	require.NoError(t, err)
	require.Len(t, analyses, 1)
	require.NotNil(t, analyses[0].MinCreatedAt)
	require.Equal(t, analyses[0].ID, analysis1.ID)
	require.Equal(t, then, analyses[0].MinCreatedAt)
}

func TestLatestAnalysesForRefWithNoTip(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()

	s := alert.TestService(db)
	toolS := tool.NewService(db, limits.TestLimitSelector())

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

	extensionA := ts.ToolFromCanonicalName("Query Pack A")
	dbtest.RequireCreate(t, db, extensionA)

	extensionB := ts.ToolFromCanonicalName("Query Pack B")
	dbtest.RequireCreate(t, db, extensionB)

	extensionC := ts.ToolFromCanonicalName("Query Pack C")
	dbtest.RequireCreate(t, db, extensionC)

	extensionAToolVersion := &ts.ToolVersion{
		ToolID:  extensionA.ID,
		Name:    extensionA.CanonicalName,
		Version: "1.0.0",
	}
	dbtest.RequireCreate(t, db, extensionAToolVersion)

	extensionBToolVersion := &ts.ToolVersion{
		ToolID:  extensionB.ID,
		Name:    extensionB.CanonicalName,
		Version: "1.0.0",
	}
	dbtest.RequireCreate(t, db, extensionBToolVersion)

	extensionCToolVersion := &ts.ToolVersion{
		ToolID:  extensionC.ID,
		Name:    extensionC.CanonicalName,
		Version: "1.0.0",
	}
	dbtest.RequireCreate(t, db, extensionCToolVersion)

	ruleA := &ts.Rule{SarifIdentifier: "a/test"}
	dbtest.RequireCreate(t, db, ruleA)

	ruleB := &ts.Rule{SarifIdentifier: "b/test"}
	dbtest.RequireCreate(t, db, ruleB)

	then := gormext.ConvertTime(ptr.Time(time.Now().Add(10 * 24 * time.Hour * -1)))

	analysis1 := &ts.Analysis{
		BaseModel: ts.BaseModel{
			CreatedAt: *then,
		},
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/master"),
		CommitOid:          "da39a3ee5e6b4b0d3255bfef95601890afd80709",
		Tool:               tool,
		ToolID:             tool.ID,
		ToolVersionID:      toolVersion.ID,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, analysis1)

	analysis2 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("refs/head/master"),
		CommitOid:          "da39a3ee5e6b4b0d3255bfef95601890afd80709",
		Tool:               tool,
		ToolID:             tool.ID,
		ToolVersionID:      toolVersion.ID,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, analysis2)

	doc := samples.RequireSARIF(t, "./testdata/toolExecutionNotifications.sarif")
	ams := analysismessage.NewService(db)

	err := toolS.CreateAnalysisExtractedFiles(ctx, analysis1, doc.Runs[0], ams)
	require.NoError(t, err)

	err = toolS.CreateAnalysisExtractedFiles(ctx, analysis2, doc.Runs[0], ams)
	require.NoError(t, err)

	analyses, err := s.LatestAnalysesForRef(ctx, repoID, defaultLatestAnalysisFilter, true)
	require.NoError(t, err)
	require.Len(t, analyses, 1)
	require.False(t, analyses[0].HasMostRecent)
}

func TestToolNotificationsAreAugmentedWithCodeScanningData(t *testing.T) {
	doc := samples.RequireSARIF(t, "./testdata/tool-status-notification-augmented-with-code-scanning-properties.sarif")
	notification := doc.Runs[0].Invocations[0].ToolExecutionNotifications[0]
	require.NotNil(t, notification.Properties)
	require.Equal(t, "https://github.com", notification.Properties.HelpLinks[0])
	require.Equal(t, "lib/test.js", notification.Locations[0].PhysicalLocation.ArtifactLocation.Uri)
	require.Equal(t, 95, notification.Locations[0].PhysicalLocation.ArtifactLocation.Index)
	require.True(t, notification.Properties.Visibility.StatusPage)
}

func TestFindAnalyses(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	opts := ts.FindOptions{
		Preloads: []string{"Tool", "ToolVersion"},
		// Sort by id to make matching deterministic
		SortBy: "ts_analyses.id desc",
	}

	s := alert.TestService(db)
	tools := tool.NewService(db, limits.TestLimitSelector())

	// Repo 1
	a1 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		CommitOid:          "XXX",
		Ref:                []byte("refs/heads/main"),
		ToolID:             requireToolByName(t, tools, 1, "CodeQL").ID,
		AnalysisKey:        "analysis-1",
		SarifID:            "424e2b7e-b0e1-47cb-8d00-51b05453bccd",
		Category:           "analysis-1",
	}
	dbtest.RequireCreate(t, db, a1)

	// Repo 2
	a2 := &ts.Analysis{
		RepositoryID:       2,
		SourceRepositoryID: 2,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/develop"),
		ToolID:             requireToolByName(t, tools, 2, "CodeQL").ID,
		AnalysisKey:        "analysis-2",
	}
	dbtest.RequireCreate(t, db, a2)
	// Repo 1, most_recent = false
	a3 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		CommitOid:          "YYY",
		Ref:                []byte("refs/heads/testing"),
		ToolID:             requireToolByName(t, tools, 1, "CodeQL").ID,
		AnalysisKey:        "analysis-3",
	}
	dbtest.RequireCreate(t, db, a3)
	// Repo 3
	a4 := &ts.Analysis{
		RepositoryID:       3,
		SourceRepositoryID: 3,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		CommitOid:          "ZZZ",
		Ref:                []byte("refs/heads/testing"),
		ToolID:             requireToolByName(t, tools, 3, "ESLint").ID,
		AnalysisKey:        "analysis-4",
	}
	dbtest.RequireCreate(t, db, a4)
	// Repo 1: PR
	a5 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		CommitOid:          "WWW",
		Ref:                []byte("refs/pull/1/head"),
		ToolID:             requireToolByName(t, tools, 1, "ESLint").ID,
		AnalysisKey:        "analysis-5",
	}
	dbtest.RequireCreate(t, db, a5)
	// Repo 1: Fork PR (Repo 99)
	a6 := &ts.Analysis{
		RepositoryID:       1,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		CommitOid:          "JJJ",
		Ref:                []byte("refs/pull/2/head"),
		ToolID:             requireToolByName(t, tools, 1, "ESLint").ID,
		AnalysisKey:        "analysis-6",
		SourceRepositoryID: 99,
	}
	dbtest.RequireCreate(t, db, a6)
	// Repo 1, analysis_complete = false
	a7 := &ts.Analysis{
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		CommitOid:          "YYY",
		Ref:                []byte("refs/heads/testing"),
		ToolID:             requireToolByName(t, tools, 1, "CodeQL").ID,
		AnalysisKey:        "analysis-3",
	}
	dbtest.RequireCreate(t, db, a7)

	repoID := ts.RepositoryEID(1)
	as, err := s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
	}, &opts)
	require.NoError(t, err)
	require.Equal(t, 5, len(as))
	require.Equal(t, a1.ID, as[4].ID)
	require.Equal(t, a3.ID, as[3].ID)
	require.Equal(t, a5.ID, as[2].ID)
	require.Equal(t, a6.ID, as[1].ID)
	require.Equal(t, a7.ID, as[0].ID)

	as, err = s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
		ToolIDs:      []ts.ToolID{requireToolByName(t, tools, 1, "ESLint").ID},
	}, &opts)
	require.NoError(t, err)
	require.Equal(t, 2, len(as))
	require.Equal(t, a5.ID, as[1].ID)
	require.Equal(t, a6.ID, as[0].ID)

	analysisCategory := ts.ToCategory("analysis-1")
	as, err = s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID:     repoID,
		AnalysisCategory: &analysisCategory,
	}, &opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(as))
	require.Equal(t, a1.ID, as[0].ID)

	as, err = s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
		Refs:         [][]byte{[]byte("refs/heads/main")},
	}, &opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(as))
	require.Equal(t, a1.ID, as[0].ID)

	// Exclude results from forks
	as, err = s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
		ExcludeFork:  true,
		State:        ts.AnalysisStateFilterMostRecent,
	}, &opts)
	require.NoError(t, err)
	require.Equal(t, 2, len(as))
	require.Equal(t, a1.ID, as[1].ID)
	require.Equal(t, a5.ID, as[0].ID)

	as, err = s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
		Refs: [][]byte{
			[]byte("refs/pull/1/head"),
			[]byte("refs/pull/2/head"),
		},
		State: ts.AnalysisStateFilterMostRecent,
	}, &opts)
	require.NoError(t, err)
	require.Equal(t, 2, len(as))
	require.True(t, a5.ID == as[1].ID)
	require.True(t, a6.ID == as[0].ID)

	// Return a full Analysis object, including the Tool association
	require.NotNil(t, as[1].Tool)

	asPtr, err := s.FindFilesExtracted(ctx, 1, []ts.AnalysisID{a1.ID, a3.ID, a5.ID, a6.ID})
	require.NoError(t, err)
	require.Len(t, asPtr, 4)
}

func TestFindAnalysesWithOptions(t *testing.T) {
	db := dbtest.RequireConnection(t)
	ctx := context.Background()

	s := alert.TestService(db)
	tools := tool.NewService(db, limits.TestLimitSelector())

	a1 := &ts.Analysis{
		ID:                 1,
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		CommitOid:          "XXX",
		Ref:                []byte("refs/heads/main"),
		ToolID:             requireToolByName(t, tools, 1, "CodeQL").ID,
		AnalysisKey:        "analysis-1",
		SarifID:            "424e2b7e-b0e1-47cb-8d00-51b05453bccd",
	}
	a1.CreatedAt = sqltime.Date(2020, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(t, db, a1)

	a2 := &ts.Analysis{
		ID:                 2,
		RepositoryID:       1,
		SourceRepositoryID: 1,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/develop"),
		ToolID:             requireToolByName(t, tools, 2, "CodeQL").ID,
		AnalysisKey:        "analysis-2",
	}
	a2.CreatedAt = sqltime.Date(2016, time.February, 16, 0, 0, 0, 0, time.UTC)
	dbtest.RequireCreate(t, db, a2)

	repoID := ts.RepositoryEID(1)
	filter := ts.AnalysisFilter{
		RepositoryID: repoID,
	}

	as, err := s.FindAnalyses(ctx, filter, nil)
	require.NoError(t, err)
	require.Equal(t, 2, len(as))

	opts := &ts.FindOptions{
		Preloads:   []string{"Tool"},
		Pagination: &ts.Pagination{Limit: 1},
		SortBy:     "ts_analyses.id desc",
	}
	as, err = s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
	}, opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(as))
	// Ordering by id DESC
	require.Equal(t, a2.ID, as[0].ID)
	// Tool should be preloaded
	require.NotNil(t, as[0].Tool)

	opts = &ts.FindOptions{
		Preloads: []string{"Tool"},
		Pagination: &ts.Pagination{
			Limit:  1,
			Offset: 1,
		},
		SortBy: "ts_analyses.id desc",
	}
	as, err = s.FindAnalyses(ctx, filter, opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(as))
	require.Equal(t, a1.ID, as[0].ID)
	require.NotNil(t, as[0].Tool)

	opts = &ts.FindOptions{
		SortBy: "ts_analyses.created_at desc, ts_analyses.id desc",
	}
	as, err = s.FindAnalyses(ctx, filter, opts)
	require.NoError(t, err)
	require.Equal(t, 2, len(as))
	// Ordering should be by CreatedAt
	require.Equal(t, a1.ID, as[0].ID)
	require.Equal(t, a2.ID, as[1].ID)

	opts = &ts.FindOptions{
		SortBy: "ts_analyses.foo",
	}
	as, err = s.FindAnalyses(ctx, filter, opts)
	require.Error(t, err)
	require.Nil(t, as)

	opts = &ts.FindOptions{}
	as, err = s.FindAnalyses(ctx, filter, opts)
	require.NoError(t, err)
	require.Equal(t, 2, len(as))
	require.Nil(t, as[0].Tool)
}

func TestFindFailedAnalyses(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := alert.TestService(db)
	ctx := context.Background()
	repoID := ts.RepositoryEID(1)

	a1 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		CommitOid:          "XXX",
		Ref:                []byte("refs/heads/master"),
		ToolID:             1,
		AnalysisName:       "analysis-1",
	}
	dbtest.RequireCreate(t, db, a1)

	sarifID2, _ := ts.NewSarifID("f37e19ea-5bc9-4897-8ab6-e73141c6ffa3")
	a2 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   false,
		MostRecent:         false,
		Ref:                []byte("refs/heads/develop"),
		ToolID:             1,
		AnalysisName:       "analysis-2",
		SarifID:            sarifID2,
	}
	dbtest.RequireCreate(t, db, a2)
	err := s.LogProcessError(ctx, ts.NewUnrecoverableAnalysisError(a2.RepositoryID, a2, "sarif error"))
	require.NoError(t, err)

	sarifID3, _ := ts.NewSarifID("c479cb47-38cf-4529-b618-e6e53ca71cbc")
	a3 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/develop"),
		ToolID:             1,
		AnalysisName:       "analysis-3",
		SarifID:            sarifID3,
	}
	dbtest.RequireCreate(t, db, a3)

	// Get 3 analyses (2 failed + 1 success)
	analyses, err := s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
	}, nil)
	require.NoError(t, err)
	require.Len(t, analyses, 3)

	// Get ProcessErrors
	require.NoError(t, err)
	messages, err := s.ProcessErrors(ctx, repoID, []ts.AnalysisID{a1.ID, a2.ID, a3.ID})
	require.NoError(t, err)
	require.Len(t, messages, 1)
	require.Len(t, messages[a2.ID], 1)
	require.Equal(t, "sarif error", messages[a2.ID][0].Message)

	// Get by SARIF ID
	analysis2, err := s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
		SarifID:      &sarifID2,
	}, nil)
	require.NoError(t, err)
	require.Len(t, analysis2, 1)
	require.Equal(t, a2.ID, analysis2[0].ID)

	analysis3, err := s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
		SarifID:      &sarifID3,
	}, nil)
	require.NoError(t, err)
	require.Len(t, analysis3, 1)
	require.Equal(t, a3.ID, analysis3[0].ID)
}

func TestAnalysisExists(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(42)
	analysisExists, err := e.as.AnalysisExists(e.ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
	})
	require.NoError(t, err)
	require.False(t, analysisExists)

	e.testLogicalAlerts(
		ts.LogicalAlert{
			RepositoryID: 42,
			Number:       2,
			RuleID:       2,
			Weight:       160,
		},
	)

	analysisExists, err = e.as.AnalysisExists(e.ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
	})
	require.NoError(t, err)
	require.True(t, analysisExists)

	otherRepoID := ts.RepositoryEID(2112)
	analysisExists, err = e.as.AnalysisExists(e.ctx, ts.AnalysisFilter{
		RepositoryID: otherRepoID,
	})
	require.NoError(t, err)
	require.False(t, analysisExists)
}

func TestLatestAnalysisCreatedAt(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(42)
	createdAt, err := e.as.LatestAnalysisCreatedAt(e.ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
	})
	require.NoError(t, err)
	require.Nil(t, createdAt)

	a1 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("ref"),
		CommitOid:          "commitoid",
		Environment:        ts.AnalysisEnv{},
		MostRecent:         true,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, a1)

	a2 := &ts.Analysis{
		BaseModel: ts.BaseModel{
			CreatedAt: sqltime.Time{Time: time.Now().Add(-1 * time.Hour)},
		},
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                []byte("ref"),
		CommitOid:          "commitoid",
		Environment:        ts.AnalysisEnv{},
		MostRecent:         false,
		AnalysisComplete:   true,
	}
	dbtest.RequireCreate(t, db, a2)

	createdAt, err = e.as.LatestAnalysisCreatedAt(e.ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
	})
	require.NoError(t, err)
	require.NotNil(t, createdAt)
	require.Equal(t, a1.CreatedAt.UTC(), createdAt.UTC())

	otherRepoID := ts.RepositoryEID(2112)
	createdAt, err = e.as.LatestAnalysisCreatedAt(e.ctx, ts.AnalysisFilter{
		RepositoryID: otherRepoID,
	})
	require.NoError(t, err)
	require.Nil(t, createdAt)
}

func TestCommit(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(42)
	codeQL := e.requireToolByName(repoID, "CodeQL")

	dbtest.RequireCount(t, 0, db.Model(&ts.Analysis{}).Where("most_recent = true"))

	a1 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		MostRecent:         true,
		AnalysisComplete:   true,
		ToolID:             codeQL.ID,
		Ref:                []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, a1)
	require.NoError(t, e.analyses.CommitAnalysis(e.ctx, a1))

	dbtest.RequireCount(t, 1, db.Model(&ts.Analysis{}).Where("id = ? AND most_recent = true", a1.ID))

	a2 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		MostRecent:         false,
		AnalysisComplete:   true,
		ToolID:             codeQL.ID,
		Ref:                []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, a2)

	a2.BaselineID = &a1.ID
	a2.MostRecent = true

	require.NoError(t, e.analyses.CommitAnalysis(e.ctx, a2))

	dbtest.RequireCount(t, 1, db.Model(&ts.Analysis{}).Where("most_recent = true"))
	dbtest.RequireCount(t, 1, db.Model(&ts.Analysis{}).Where("id = ? AND most_recent = true", a2.ID))

	a3 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		MostRecent:         false,
		AnalysisComplete:   true,
		ToolID:             codeQL.ID,
		Ref:                []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, a3)

	// We pretend `a3` came in around the same time as `a2` and got the same baseline,
	// but since `a2` finished first we should reject setting `a3` as `most_recent`. Any results in `a2` were computed
	// against the old baseline and may be inaccurate.
	a3.BaselineID = &a1.ID
	a3.MostRecent = true

	err := e.analyses.CommitAnalysis(e.ctx, a3)

	require.Error(t, err)
	require.Contains(t, err.Error(), fmt.Sprintf("could not update most_recent analysis from %d to %d", a1.ID, a3.ID))

	dbtest.RequireCount(t, 1, db.Model(&ts.Analysis{}).Where("most_recent = true"))
	dbtest.RequireCount(t, 1, db.Model(&ts.Analysis{}).Where("id = ? AND most_recent = true", a2.ID))

	a4 := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		MostRecent:         false,
		AnalysisComplete:   true,
		ToolID:             codeQL.ID,
		Ref:                []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, a4)

	// We pretend the processing of `a4` started at the same time as `a1` but went so slowly a baseline has already been
	// assigned. Setting `a4` as `most_recent` will be rejected _and_ the error message will still be helpful
	// despite `a4.BaselineID` being `nil`.
	a4.MostRecent = true

	err = e.analyses.CommitAnalysis(e.ctx, a4)

	require.Error(t, err)
	require.Contains(t, err.Error(), fmt.Sprintf("could not update most_recent analysis from <no baseline> to %d", a4.ID))

	dbtest.RequireCount(t, 1, db.Model(&ts.Analysis{}).Where("most_recent = true"))
	dbtest.RequireCount(t, 1, db.Model(&ts.Analysis{}).Where("id = ? AND most_recent = true", a2.ID))
}

func TestAnalysisExistsWithToolAndRefFilter(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(42)
	codeQL := e.requireToolByName(repoID, "CodeQL")

	l := &ts.LogicalAlert{
		RepositoryID:          repoID,
		Number:                1,
		StableAlertIdentifier: newStableID(),
	}
	dbtest.RequireCreate(t, db, &l)

	a := ts.Analysis{
		RepositoryID:       l.RepositoryID,
		SourceRepositoryID: l.RepositoryID,
		MostRecent:         true,
		AnalysisComplete:   true,
		ToolID:             codeQL.ID,
		Ref:                []byte("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, &a)

	now := sqltime.Now()
	p := &ts.PhysicalAlert{
		LogicalAlertID:        l.ID,
		RepositoryID:          l.RepositoryID,
		StableAlertIdentifier: l.StableAlertIdentifier,
		AnalysisID:            a.ID,
		RuleID:                l.RuleID,
		LastStateChangeAt:     now,
	}
	dbtest.RequireCreate(t, db, &p)

	analysisExists, err := e.as.AnalysisExists(e.ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
	})
	require.NoError(t, err)
	require.True(t, analysisExists)

	analysisExists, err = e.as.AnalysisExists(e.ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
		ToolIDs:      []ts.ToolID{codeQL.ID},
	})
	require.NoError(t, err)
	require.True(t, analysisExists)

	esLint := e.requireToolByName(repoID, "ESLint")
	analysisExists, err = e.as.AnalysisExists(e.ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
		ToolIDs:      []ts.ToolID{esLint.ID},
	})
	require.NoError(t, err)
	require.False(t, analysisExists)

	analysisExists, err = e.as.AnalysisExists(e.ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
		ToolIDs:      []ts.ToolID{codeQL.ID},
		Refs:         [][]byte{[]byte("refs/heads/other_branch"), []byte("refs/heads/main")},
	})
	require.NoError(t, err)
	require.True(t, analysisExists)

	analysisExists, err = e.as.AnalysisExists(e.ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
		ToolIDs:      []ts.ToolID{codeQL.ID},
		Refs:         [][]byte{[]byte("refs/heads/other_branch"), []byte("refs/heads/develop")},
	})
	require.NoError(t, err)
	require.False(t, analysisExists)
}

func TestAnalysisArchivalState(t *testing.T) {
	db := dbtest.RequireConnection(t)
	s := alert.TestService(db)
	repoID := ts.RepositoryEID(1)
	now := time.Now()

	analysis := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         false,
		Ref:                []byte("refs/heads/bbb"),
		ToolID:             1,
	}
	require.Equal(t, analysis.ArchivalState, ts.ArchivalState_LIVE)
	require.Equal(t, "LIVE", analysis.ArchivalState.String())

	analysis.CreatedAt = sqltime.Time{Time: now.Add(-10 * time.Minute)}
	dbtest.RequireCreate(t, db, analysis)

	ctx := context.Background()
	opts := ts.FindOptions{}
	as, err := s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
	}, &opts)
	require.NoError(t, err)
	fresh := as[0]
	require.Equal(t, ts.ArchivalState_LIVE, fresh.ArchivalState)

	analysis.ArchivalState = ts.ArchivalState_SARIF_CREATED
	err = db.Save(analysis).Error
	require.NoError(t, err)

	as, err = s.FindAnalyses(ctx, ts.AnalysisFilter{
		RepositoryID: repoID,
	}, &opts)
	require.NoError(t, err)
	fresh = as[0]
	require.Equal(t, ts.ArchivalState_SARIF_CREATED, fresh.ArchivalState)
	require.Equal(t, "SARIF_CREATED", fresh.ArchivalState.String())
}

func TestOverflowWarning(t *testing.T) {
	db := dbtest.RequireConnection(t)
	repoID := ts.RepositoryEID(1)
	a := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/bbb"),
		ToolID:             1,
	}

	a.AddWarning(strings.Repeat("f", 2048))
	dbtest.RequireCreate(t, db, a)

	b := &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Environment:        ts.AnalysisEnv{},
		AnalysisComplete:   true,
		MostRecent:         true,
		Ref:                []byte("refs/heads/bbb"),
		ToolID:             1,
	}

	b.AddWarning(strings.Repeat("f", 2049))
	require.ErrorIs(t, db.Create(b).Error, ts.ErrAnalysisProcessWarningOverflow)
}

func TestOutdatedNoBaseline(t *testing.T) {
	// When marking a configuration as outdated when there is no baseline
	// it should fail the delivery rather than create a new configuration

	db := dbtest.RequireConnection(t)

	s := analysis.NewService(db)
	ctx := context.Background()

	codeQL := &ts.Tool{CanonicalName: "CodeQL", GUID: "aaa"}
	notCodeQL := &ts.Tool{CanonicalName: "Not CodeQL", GUID: "bbb"}
	dbtest.RequireCreate(t, db, codeQL)
	dbtest.RequireCreate(t, db, notCodeQL)

	startTime := sqltime.Date(2017, time.February, 16, 0, 0, 0, 0, time.UTC)

	markAsOutdated := testAnalysis(db, ts.RepositoryEID(64), "deadbeef", "main", "analysis1", codeQL, map[string]string{}, &startTime)
	markAsOutdated.IsOutdated = true

	err := s.CreateAnalysis(ctx, markAsOutdated)
	require.Error(t, err)
	require.ErrorContains(t, err, "Cannot create an outdated analysis with no baseline analysis")
}

func TestOutdatedNoBaselineWithFailed(t *testing.T) {
	// When marking a configuration as outdated when there no baseline
	// all failed analyses should be soft deleted for the configuration

	db := dbtest.RequireConnection(t)

	s := analysis.NewService(db)
	ctx := context.Background()

	codeQL := &ts.Tool{CanonicalName: "CodeQL", GUID: "aaa"}
	notCodeQL := &ts.Tool{CanonicalName: "Not CodeQL", GUID: "bbb"}
	dbtest.RequireCreate(t, db, codeQL)
	dbtest.RequireCreate(t, db, notCodeQL)

	startTime := sqltime.Date(2017, time.February, 16, 0, 0, 0, 0, time.UTC)

	failed1 := testAnalysis(db, ts.RepositoryEID(64), "deadbeef", "main", "analysis1", codeQL, map[string]string{}, &startTime)
	failed1.Failed = true
	failed1.AnalysisComplete = true

	failed2 := testAnalysis(db, ts.RepositoryEID(64), "deadbeef", "main", "analysis1", codeQL, map[string]string{}, &startTime)
	failed2.Failed = true
	failed2.AnalysisComplete = true

	err := db.Save(failed1).Error
	require.NoError(t, err)
	err = db.Save(failed2).Error
	require.NoError(t, err)

	var arr []*ts.Analysis

	db.Find(&arr)
	require.Equal(t, 2, len(arr))

	markAsOutdated := testAnalysis(db, ts.RepositoryEID(64), "deadbeef", "main", "analysis1", codeQL, map[string]string{}, &startTime)
	markAsOutdated.IsOutdated = true

	err = s.CreateAnalysis(ctx, markAsOutdated)
	require.Error(t, err)
	require.ErrorContains(t, err, "Cannot create an outdated analysis with no baseline analysis")

	var endArr []*ts.Analysis

	db.Find(&endArr)
	require.Equal(t, 2, len(endArr))

	require.NotNil(t, endArr[0].SoftDeletedAt)
	require.NotNil(t, endArr[1].SoftDeletedAt)
}

func TestOutdatedWithOutdatedBaseline(t *testing.T) {
	// When re-marking as outdated, the analysis should fail the delivery
	// but it should soft delete any failed analyses since the outdated baseline

	db := dbtest.RequireConnection(t)

	s := analysis.NewService(db)
	ctx := context.Background()

	codeQL := &ts.Tool{CanonicalName: "CodeQL", GUID: "aaa"}
	notCodeQL := &ts.Tool{CanonicalName: "Not CodeQL", GUID: "bbb"}
	dbtest.RequireCreate(t, db, codeQL)
	dbtest.RequireCreate(t, db, notCodeQL)

	startTime := sqltime.Date(2017, time.February, 16, 0, 0, 0, 0, time.UTC)

	failed1 := testAnalysis(db, ts.RepositoryEID(64), "deadbeef", "main", "analysis1", codeQL, map[string]string{}, &startTime)
	failed1.Failed = true
	failed1.AnalysisComplete = true

	failed2 := testAnalysis(db, ts.RepositoryEID(64), "deadbeef", "main", "analysis1", codeQL, map[string]string{}, &startTime)
	failed2.Failed = true
	failed2.AnalysisComplete = true

	err := db.Save(failed1).Error
	require.NoError(t, err)
	err = db.Save(failed2).Error
	require.NoError(t, err)

	success := testAnalysis(db, ts.RepositoryEID(64), "deadbeef", "main", "analysis1", codeQL, map[string]string{}, &startTime)

	err = s.CreateAnalysis(ctx, success)
	require.NoError(t, err)

	err = s.CommitAnalysis(ctx, success)
	require.NoError(t, err)

	markAsOutdated := testAnalysis(db, ts.RepositoryEID(64), "deadbeef", "main", "analysis1", codeQL, map[string]string{}, &startTime)
	markAsOutdated.IsOutdated = true

	err = s.CreateAnalysis(ctx, markAsOutdated)
	require.NoError(t, err)

	err = s.CommitAnalysis(ctx, markAsOutdated)
	require.NoError(t, err)

	failedAfterOutdated := testAnalysis(db, ts.RepositoryEID(64), "deadbeef", "main", "analysis1", codeQL, map[string]string{}, &startTime)
	failedAfterOutdated.Failed = true
	failedAfterOutdated.AnalysisComplete = true

	err = db.Save(failedAfterOutdated).Error
	require.NoError(t, err)

	var arr []*ts.Analysis

	db.Find(&arr)
	require.Equal(t, 5, len(arr))

	markAsOutdatedAgain := testAnalysis(db, ts.RepositoryEID(64), "deadbeef", "main", "analysis1", codeQL, map[string]string{}, &startTime)
	markAsOutdatedAgain.IsOutdated = true

	err = s.CreateAnalysis(ctx, markAsOutdated)
	require.Error(t, err)
	require.ErrorContains(t, err, "Cannot create an analysis that's outdated with an already outdated baseline")

	var endArr []*ts.Analysis

	db.Find(&endArr)
	require.Equal(t, 5, len(endArr))

	// Failed analysis before the baseline are not touched
	require.Nil(t, endArr[0].SoftDeletedAt)
	require.Nil(t, endArr[1].SoftDeletedAt)
	require.Nil(t, endArr[2].SoftDeletedAt)
	require.Nil(t, endArr[3].SoftDeletedAt)
	require.Equal(t, endArr[2].IsOutdated, false)
	require.Equal(t, endArr[2].Failed, false)
	require.Equal(t, endArr[3].IsOutdated, true)
	require.Equal(t, endArr[3].Failed, false)
	require.Equal(t, endArr[3].MostRecent, true)

	// Failed analysis after the baseline are soft deleted
	require.NotNil(t, endArr[4].SoftDeletedAt)
}
