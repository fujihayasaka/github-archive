package processor

import (
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/mysql/archiver"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/transforms"
	"github.com/stretchr/testify/require"
	"golang.org/x/exp/maps"
)

func TestPRAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(1)
	baseRef := "base"
	headRef := "head"
	mergeRef := "merge"
	var baseCommit ts.Sha = "baseCommit"
	var headCommit ts.Sha = "headCommit"
	var mergeCommit ts.Sha = "mergeCommit"
	category := "category"
	categoryOld := "categoryOld"
	missingCategory := ts.ToCategory("missingCategory")
	missingCategoryOld := "missingCategoryOld"
	newCategory := ts.ToCategory("newCategory")
	codeQL := requireToolByName(t, e.tools, 1, "CodeQL")

	// Create base analysis
	base := testConfig{
		repositoryID: repoID,
		ref:          baseRef,
		commitOid:    baseCommit,
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	}
	_ = e.deliverAlerts(base, testAlert("F1", "P1_base"))

	// Create analysis for a category that will be missing in the head
	baseMissingCat := testConfig{
		repositoryID: repoID,
		ref:          baseRef,
		commitOid:    baseCommit,
		analysisKey:  missingCategory.String(),
		tool:         codeQL.CanonicalName,
	}
	_ = e.deliverAlerts(baseMissingCat, testAlert("F0", "P0_base_missing_cat"))

	// Create analysis for an _outdated_ category that will be missing in the head
	baseOldMissingCat := testConfig{
		repositoryID: repoID,
		ref:          baseRef,
		commitOid:    baseCommit,
		analysisKey:  missingCategoryOld,
		tool:         codeQL.CanonicalName,
	}
	oldAnalysis := e.deliverAlerts(baseOldMissingCat, testAlert("F0", "P0_base_old_missing_cat"))
	err := db.Model(&ts.Analysis{}).
		Where("id = ?", oldAnalysis.ID).
		UpdateColumn("created_at", sqltime.Time{Time: time.Now().Add(-24 * time.Hour * 180)}).Error
	require.NoError(t, err)

	// Create analysis for an _outdated_ category that will be present in the head
	oldCat := testConfig{
		repositoryID: repoID,
		ref:          baseRef,
		commitOid:    baseCommit,
		analysisKey:  categoryOld,
		tool:         codeQL.CanonicalName,
	}
	oldAnalysis = e.deliverAlerts(oldCat)
	err = db.Model(&ts.Analysis{}).
		Where("id = ?", oldAnalysis.ID).
		UpdateColumn("created_at", sqltime.Time{Time: time.Now().Add(-24 * time.Hour * 180)}).Error
	require.NoError(t, err)

	oldCat.ref = mergeRef
	oldCat.commitOid = mergeCommit
	_ = e.deliverAlerts(oldCat)

	// Deliver alerts for the merge commit
	merge := testConfig{
		repositoryID: repoID,
		ref:          mergeRef,
		commitOid:    mergeCommit,
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	}
	_ = e.deliverAlerts(merge, testAlert("F1", "P1_merge"), testAlert("F2", "P2_merge"))

	// Deliver alerts for a new category on merge commit
	mergeNewCat := testConfig{
		repositoryID: repoID,
		ref:          mergeRef,
		commitOid:    mergeCommit,
		analysisKey:  newCategory.String(),
		tool:         codeQL.CanonicalName,
	}
	mergeAnalysis := e.deliverAlerts(mergeNewCat, testAlert("F3", "P3_merge_new_cat"))

	mergeAnalysisUploadFinishedAt := time.Now().Add(-3 * time.Minute).Truncate(time.Second).UTC() // 3 minutes ago has no special meaning, just an arbitrary recent datetime
	err = db.Model(&ts.Analysis{}).
		Where("id = ?", mergeAnalysis.ID).
		UpdateColumn("upload_finished_at", sqltime.Time{Time: mergeAnalysisUploadFinishedAt}).Error
	require.NoError(t, err)

	// Deliver alerts for the head commit
	head := testConfig{
		repositoryID: repoID,
		ref:          headRef,
		commitOid:    headCommit,
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	}
	_ = e.deliverAlerts(head, testAlert("F1", "P1_head"), testAlert("F4", "P4_head"))
	// Alert on F4 is not expected as the merge analysis has higher priority so the head analysis should not be used

	fileChanges := make([]*proto.FileChange, 0)
	fileChanges = append(fileChanges,
		&proto.FileChange{
			FilePath: "F2",
			Changes: []*proto.Change{
				{
					Added:     true,
					StartLine: 1,
					EndLine:   1,
				},
			},
		},
		&proto.FileChange{
			FilePath: "F3",
			Changes: []*proto.Change{
				{
					Added:     true,
					StartLine: 1,
					EndLine:   1,
				},
			},
		},
		&proto.FileChange{
			FilePath: "F4",
			Changes: []*proto.Change{
				{
					Added:     true,
					StartLine: 1,
					EndLine:   1,
				},
			},
		},
	)
	ops := &ts.PRAlertsOpts{
		AfterCommits: []ts.Sha{mergeCommit, headCommit},
		BaseRef:      baseRef,
		ToolIDs:      []ts.ToolID{codeQL.ID},
		FileChanges:  fileChanges,
	}
	prAlerts, err := e.prAlertsService.PullRequestAlerts(e.ctx, e.archiveService, repoID, ops)
	require.NoError(t, err)

	require.Equal(t, 1, len(prAlerts.NewCategories))
	require.NotNil(t, prAlerts.NewCategories[newCategory])

	require.Equal(t, 1, len(prAlerts.MissingCategories))
	require.Equal(t, []ts.Category{missingCategory}, maps.Keys(prAlerts.MissingCategories))
	require.Equal(t, ts.DeliveryOrigin_YML, prAlerts.MissingCategories[missingCategory].DeliveryOrigin)

	require.Equal(t, 2, len(prAlerts.NewAlerts))
	require.ElementsMatch(t, []string{"F2", "F3"}, []string{prAlerts.NewAlerts[0].SarifIdentifier, prAlerts.NewAlerts[1].SarifIdentifier})

	require.Equal(t, mergeAnalysisUploadFinishedAt, prAlerts.LatestUploadTime.Time)

	ctx := flipper.WithFeatureEnabled(e.ctx, flipper.CodeScanningSuggestedFixAllQueries)
	prAlerts, err = e.prAlertsService.PullRequestAlerts(ctx, e.archiveService, repoID, ops)
	require.NoError(t, err)
	require.Equal(t, 2, len(prAlerts.NewAlerts))
	require.Equal(t, "F2", prAlerts.NewAlerts[0].PhysicalAlerts[0].FilePath)
	require.Equal(t, "F3", prAlerts.NewAlerts[1].PhysicalAlerts[0].FilePath)
}

func TestPRAlertsRelatedLocations(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(1)
	baseRef := "base"
	mergeRef := "merge"
	baseCommit := ts.ToSha("baseCommit")
	mergeCommit := ts.ToSha("mergeCommit")
	category := "category"
	codeQL := requireToolByName(t, e.tools, 1, "CodeQL")

	// Create base analysis
	_ = e.deliverAlerts(testConfig{
		repositoryID: repoID,
		ref:          baseRef,
		commitOid:    baseCommit,
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	})

	// We'll have line 10 be the one that changes and have one alert touching
	// that line in each of the three ways
	_ = e.deliverAlerts(testConfig{
		repositoryID: repoID,
		ref:          mergeRef,
		commitOid:    mergeCommit,
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	},
		testAlertT{filePath: "F", paKey: "P1", resultLine: 10},
		testAlertT{filePath: "G", paKey: "P2", relatedPath: "F", relatedLine: 10},
		testAlertT{filePath: "G", paKey: "P3", codeFlowPath: "F", codeFlowLine: 10})

	fileChanges := make([]*proto.FileChange, 0)
	fileChanges = append(fileChanges,
		&proto.FileChange{
			FilePath: "F",
			Changes: []*proto.Change{
				{
					Added:     true,
					StartLine: 10,
					EndLine:   10,
				},
			},
		},
	)
	ops := &ts.PRAlertsOpts{
		AfterCommits: []ts.Sha{mergeCommit},
		BaseRef:      baseRef,
		ToolIDs:      []ts.ToolID{codeQL.ID},
		FileChanges:  fileChanges,
	}
	prAlerts, err := e.prAlertsService.PullRequestAlerts(e.ctx, e.archiveService, repoID, ops)
	require.NoError(t, err)
	require.ElementsMatch(t,
		transforms.Map([]string{"P1", "P2"}, func(s string) string { return e.paGuids[s] }),
		transforms.Map(prAlerts.NewAlerts, func(a *ts.LogicalAlert) string { return *a.PhysicalAlerts[0].GUID }),
	)
}

func TestPRAlertsArchivedOnly(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(1)
	baseRef := "base"
	headRef := "head"
	category := "category"
	codeQL := requireToolByName(t, e.tools, 1, "CodeQL")

	base := testConfig{
		repositoryID: repoID,
		ref:          baseRef,
		commitOid:    "B",
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	}
	_ = e.deliverAlerts(base, testAlert("F1", "P1_B"))

	head := testConfig{
		repositoryID: repoID,
		ref:          headRef,
		commitOid:    "X",
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	}
	x := e.deliverAlerts(head, testAlert("F2", "P1_X"))

	head.commitOid = "Y"
	_ = e.deliverAlerts(head, testAlert("F3", "P1_Y"))

	err := e.archiveService.FullArchive(e.ctx, repoID, x.ID, archiver.ArchiveOpts{StrictVerify: true, Delete: true})
	require.NoError(t, err)

	fileChanges := []*proto.FileChange{
		{
			FilePath: "F1",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
		{
			FilePath: "F2",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
		{
			FilePath: "F3",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}
	ops := &ts.PRAlertsOpts{
		AfterCommits: []ts.Sha{"X"},
		BaseRef:      baseRef,
		ToolIDs:      []ts.ToolID{codeQL.ID},
		FileChanges:  fileChanges,
	}

	prAlerts, err := e.prAlertsService.PullRequestAlerts(e.ctx, e.archiveService, repoID, ops)
	require.NoError(t, err)
	require.Equal(t, 1, len(prAlerts.NewAlerts))
	require.Equal(t, e.paGuids["P1_X"], *prAlerts.NewAlerts[0].PhysicalAlerts[0].GUID)
}

func TestPRAlertsReturnsFixed(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(1)
	baseRef := "base"
	headRef := "head"
	category := "category"
	codeQL := requireToolByName(t, e.tools, 1, "CodeQL")

	base := testConfig{
		repositoryID: repoID,
		ref:          baseRef,
		commitOid:    "B",
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	}
	_ = e.deliverAlerts(base, testAlert("F1", "P1_B"))

	head := testConfig{
		repositoryID: repoID,
		ref:          headRef,
		commitOid:    "X",
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	}
	_ = e.deliverAlerts(head, testAlert("F2", "P1_X"))

	// With only an addition, we only get the one new alert
	fileChanges := []*proto.FileChange{
		{
			FilePath: "F2",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}
	opts := &ts.PRAlertsOpts{
		AfterCommits: []ts.Sha{"X"},
		BaseRef:      baseRef,
		ToolIDs:      []ts.ToolID{codeQL.ID},
		FileChanges:  fileChanges,
	}

	prAlerts, err := e.prAlertsService.PullRequestAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(prAlerts.NewAlerts))
	require.Empty(t, len(prAlerts.FixedAlerts))
	require.Equal(t, e.paGuids["P1_X"], *prAlerts.NewAlerts[0].PhysicalAlerts[0].GUID)

	// With only a deletion, we only get the one fixed alert
	opts.FileChanges = []*proto.FileChange{
		{
			FilePath: "F1",
			Changes:  []*proto.Change{{Added: false, StartLine: 1, EndLine: 1}},
		},
	}

	prAlerts, err = e.prAlertsService.PullRequestAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(prAlerts.FixedAlerts))
	require.Empty(t, len(prAlerts.NewAlerts))
	require.Equal(t, e.paGuids["P1_B"], *prAlerts.FixedAlerts[0].PhysicalAlerts[0].GUID)

	// With both, we get new and fixed
	opts.FileChanges = []*proto.FileChange{
		{
			FilePath: "F1",
			Changes:  []*proto.Change{{Added: false, StartLine: 1, EndLine: 1}},
		},
		{
			FilePath: "F2",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}

	prAlerts, err = e.prAlertsService.PullRequestAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(prAlerts.FixedAlerts))
	require.Equal(t, 1, len(prAlerts.NewAlerts))
	require.Equal(t, e.paGuids["P1_X"], *prAlerts.NewAlerts[0].PhysicalAlerts[0].GUID)
	require.Equal(t, e.paGuids["P1_B"], *prAlerts.FixedAlerts[0].PhysicalAlerts[0].GUID)
}
