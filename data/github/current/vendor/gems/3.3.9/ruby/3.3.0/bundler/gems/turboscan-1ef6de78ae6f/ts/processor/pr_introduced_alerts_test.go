package processor

import (
	"sort"
	"testing"
	"time"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/mysql/archiver"
	"github.com/github/turboscan/ts/proto"
	"github.com/stretchr/testify/require"
)

func TestPRIntroducedAlertsArchivedOnly(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(1)
	baseRef := "base"
	prNumber := uint32(42)
	headRef := "refs/pull/42/head"
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
	ma := e.deliverAlerts(head, testAlert("F2", "P1_X"), testAlert("F3", "P1_Y"))

	err := e.archiveService.FullArchive(e.ctx, repoID, x.ID, archiver.ArchiveOpts{StrictVerify: true, Delete: true})
	require.NoError(t, err)

	fileChanges := []*proto.FileChange{
		{
			FilePath: "F2",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
		{
			FilePath: "F3",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}
	opts := &ts.PRAlertsOpts{
		BaseRef:     baseRef,
		ToolIDs:     []ts.ToolID{codeQL.ID},
		FileChanges: fileChanges,
		PRNumber:    prNumber,
	}

	alerts, err := e.prAlertsService.PullRequestIntroducedAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 2, len(alerts))
	sort.Slice(alerts, func(i, j int) bool {
		return alerts[i].IntroducedAt.Time.Before(alerts[j].IntroducedAt.Time)
	})
	alert := alerts[0].PhysicalAlert
	require.Equal(t, e.paGuids["P1_X"], *alert.GUID)
	require.Equal(t, uint32(2), alert.LogicalAlert.Number)
	require.Equal(t, "CodeQL", alert.Analysis.Tool.CanonicalName.String())
	require.False(t, alert.IsFixed)

	alert = alerts[1].PhysicalAlert
	require.Equal(t, e.paGuids["P1_Y"], *alert.GUID)
	require.Equal(t, uint32(3), alert.LogicalAlert.Number)

	// Now a new push that fixes first alert
	head.commitOid = "Z"
	a := e.deliverAlerts(head, testAlert("F2", "P1_X"), testAlert("F3", "P1_Y"))
	pa := a.PhysicalAlerts[0]
	pa.LastSeenAnalysisID = &ma.ID
	pa.LastStateChangeAt = sqltime.Now()
	require.NoError(t, db.Save(&pa).Error)

	// Archive previous analysis
	err = e.archiveService.FullArchive(e.ctx, repoID, ma.ID, archiver.ArchiveOpts{StrictVerify: true, Delete: true})
	require.NoError(t, err)

	opts.FileChanges = []*proto.FileChange{
		{
			FilePath: "F3",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}
	alerts, err = e.prAlertsService.PullRequestIntroducedAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 2, len(alerts))
	sort.Slice(alerts, func(i, j int) bool {
		return alerts[i].IntroducedAt.Time.Before(alerts[j].IntroducedAt.Time)
	})
	for i, a := range alerts {
		if i == 0 {
			require.True(t, a.PhysicalAlert.IsFixed)
		} else {
			require.False(t, a.PhysicalAlert.IsFixed)
		}
		// check the required associations
		require.NotNil(t, a.PhysicalAlert.LogicalAlert, "LogicalAlert should not be nil for alert %d", i)
		require.NotNil(t, a.PhysicalAlert.Analysis)
		require.NotNil(t, a.PhysicalAlert.Analysis.Tool)
	}
}

func TestPRIntroducedAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(1)
	baseRef := "base"
	prNumber := uint32(42)
	headRef := "refs/pull/42/head"
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
		BaseRef:     baseRef,
		ToolIDs:     []ts.ToolID{codeQL.ID},
		FileChanges: fileChanges,
		PRNumber:    prNumber,
	}

	alerts, err := e.prAlertsService.PullRequestIntroducedAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(alerts))
	require.Equal(t, e.paGuids["P1_X"], *alerts[0].PhysicalAlert.GUID)
	require.Equal(t, uint32(2), alerts[0].PhysicalAlert.LogicalAlert.Number)

	// new push to head(PR)
	head = testConfig{
		repositoryID: repoID,
		ref:          headRef,
		commitOid:    "Xa",
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	}
	// With new alert
	ma := e.deliverAlerts(head, testAlert("F2", "P1_X"), testAlert("F3", "P1_Y"))
	// Update the analysis created at to be in the past
	// to make sure we wont get any inconsistency in tests due to time difference
	at := time.Now().Add(-5 * time.Minute).Truncate(time.Second).UTC()
	err = db.Model(&ts.Analysis{}).
		Where("id = ?", ma.ID).
		UpdateColumn("created_at", sqltime.Time{Time: at}).Error
	require.NoError(t, err)

	opts.FileChanges = []*proto.FileChange{
		{
			FilePath: "F2",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
		{
			FilePath: "F3",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}
	alerts, err = e.prAlertsService.PullRequestIntroducedAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 2, len(alerts))
	sort.Slice(alerts, func(i, j int) bool {
		return alerts[i].IntroducedAt.Time.Before(alerts[j].IntroducedAt.Time)
	})
	alert := alerts[0].PhysicalAlert
	require.Equal(t, e.paGuids["P1_X"], *alert.GUID)
	require.Equal(t, uint32(2), alert.LogicalAlert.Number)
	require.Equal(t, "CodeQL", alert.Analysis.Tool.CanonicalName.String())
	require.False(t, alert.IsFixed)

	alert = alerts[1].PhysicalAlert
	require.Equal(t, e.paGuids["P1_Y"], *alert.GUID)
	require.Equal(t, uint32(3), alert.LogicalAlert.Number)

	// Now a new push that fixes both alerts
	head = testConfig{
		repositoryID: repoID,
		ref:          headRef,
		commitOid:    "Xb",
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	}
	analysis := e.deliverAlerts(head, testAlert("F2", "P1_X"), testAlert("F3", "P1_Y"))

	for _, pa := range analysis.PhysicalAlerts {
		pa.LastSeenAnalysisID = &ma.ID
		pa.LastStateChangeAt = sqltime.Now()
		err = db.Save(pa).Error
		require.NoError(t, err)
	}
	// Some random file change, not related to the alerts
	opts.FileChanges = []*proto.FileChange{
		{
			FilePath: "bar.js",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}
	alerts, err = e.prAlertsService.PullRequestIntroducedAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 2, len(alerts))
	for _, a := range alerts {
		require.True(t, a.PhysicalAlert.IsFixed)
		require.NotNil(t, a.FixedAt)
		require.Equal(t, *a.FixedAt, analysis.CreatedAt)
	}
}

func TestPRIntroducedAlertsWithDismissedAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(1)
	baseRef := "base"
	prNumber := uint32(42)
	headRef := "refs/pull/42/head"
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
	analysis := e.deliverAlerts(head, testAlert("F2", "P1_X"))

	// With only an addition, we only get the one new alert
	fileChanges := []*proto.FileChange{
		{
			FilePath: "F2",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}
	opts := &ts.PRAlertsOpts{
		BaseRef:     baseRef,
		ToolIDs:     []ts.ToolID{codeQL.ID},
		FileChanges: fileChanges,
		PRNumber:    prNumber,
	}

	alerts, err := e.prAlertsService.PullRequestIntroducedAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(alerts))
	require.Equal(t, e.paGuids["P1_X"], *alerts[0].PhysicalAlert.GUID)
	require.Equal(t, uint32(2), alerts[0].PhysicalAlert.LogicalAlert.Number)

	// dismiss alert
	err = db.Model(&ts.LogicalAlert{}).
		Where("id = ?", analysis.PhysicalAlerts[0].LogicalAlert.ID).
		UpdateColumn("resolution", ts.AlertResolutionFalsePositive).Error
	require.NoError(t, err)

	alerts, err = e.prAlertsService.PullRequestIntroducedAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(alerts))
}

// TestPRIntroducedAlertsFixNonIntroduced tests this fix: github/code-scanning#15177
func TestPRIntroducedAlertsFixNonIntroduced(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(1)
	baseRef := "base"
	prNumber := uint32(42)
	headRef := "refs/pull/42/head"
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
	// First PR analysis contain a new alert
	_ = e.deliverAlerts(head, testAlert("F1", "P1_B"), testAlert("F2", "P1_X"))

	// With only an addition, we only get the one new alert
	fileChanges := []*proto.FileChange{
		{
			FilePath: "F2",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}
	opts := &ts.PRAlertsOpts{
		BaseRef:     baseRef,
		ToolIDs:     []ts.ToolID{codeQL.ID},
		FileChanges: fileChanges,
		PRNumber:    prNumber,
	}

	alerts, err := e.prAlertsService.PullRequestIntroducedAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(alerts))
	require.Equal(t, e.paGuids["P1_X"], *alerts[0].PhysicalAlert.GUID)
	require.Equal(t, uint32(2), alerts[0].PhysicalAlert.LogicalAlert.Number)

	// Fix the alert that existed in base
	head.commitOid = "Xx"
	_ = e.deliverAlerts(head, testAlert("F2", "P1_X"))
	alerts, err = e.prAlertsService.PullRequestIntroducedAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 1, len(alerts))
	// Should not return the fixed alert, as that was not introduced in the PR
	require.Equal(t, e.paGuids["P1_X"], *alerts[0].PhysicalAlert.GUID)
}

func TestPRIntroducedAlertsFixNonIntroducedGap(t *testing.T) {
	db := dbtest.RequireConnection(t)
	e := requireTestEnv(t, db)

	repoID := ts.RepositoryEID(1)
	baseRef := "base"
	prNumber := uint32(42)
	headRef := "refs/pull/42/head"
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
	// Now is fixed on base
	base.commitOid = "Bx"
	_ = e.deliverAlerts(base)

	head := testConfig{
		repositoryID: repoID,
		ref:          headRef,
		commitOid:    "X",
		analysisKey:  category,
		tool:         codeQL.CanonicalName,
	}
	// Re-introduce the alert(F1), in the first analysis
	_ = e.deliverAlerts(head, testAlert("F1", "P1_B"), testAlert("F2", "P1_X"))

	// With only an addition, we only get the one new alert
	fileChanges := []*proto.FileChange{
		{
			FilePath: "F1",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
		{
			FilePath: "F2",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}
	opts := &ts.PRAlertsOpts{
		BaseRef:     baseRef,
		ToolIDs:     []ts.ToolID{codeQL.ID},
		FileChanges: fileChanges,
		PRNumber:    prNumber,
	}

	alerts, err := e.prAlertsService.PullRequestIntroducedAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)
	require.Equal(t, 2, len(alerts))

	// Fix the alert that existed in base
	head.commitOid = "Xx"
	_ = e.deliverAlerts(head, testAlert("F2", "P1_X"))
	opts.FileChanges = []*proto.FileChange{
		{
			FilePath: "F2",
			Changes:  []*proto.Change{{Added: true, StartLine: 1, EndLine: 1}},
		},
	}
	alerts, err = e.prAlertsService.PullRequestIntroducedAlerts(e.ctx, e.archiveService, repoID, opts)
	require.NoError(t, err)

	// Here is the problem we should return 2 alerts.
	// As F1 was re-introduced in the first analysis, and fixed afterwards
	// see github/turboscan#6933
	require.Equal(t, 1, len(alerts))
}
