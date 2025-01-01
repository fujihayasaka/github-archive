package suggestedfixes

import (
	"context"
	"fmt"
	"testing"

	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/archiver"
	"github.com/github/turboscan/ts/sarif/store"

	"github.com/SamuelTissot/sqltime"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
)

func TestSuggestedFixes_SaveFixes(t *testing.T) {
	db := dbtest.RequireConnection(t)
	sfdb := suggestedfixes.NewService(db)
	ctx := context.Background()
	_ = ctx

	alertService := alert.TestService(db)

	alert := &ts.PhysicalAlert{
		ID: ts.PhysicalAlertID(1),
		Region: ts.Region{
			StartLine:   1,
			StartColumn: 5,
			EndColumn:   10,
			EndLine:     1,
		},
		RuleSarifIdentifier: "js/reflected-xss",
		LogicalAlert: &ts.LogicalAlert{
			ID:       ts.LogicalAlertID(1),
			Number:   1,
			FilePath: "foo/bar.js",
		},
		RepositoryID: ts.RepositoryEID(1),
	}

	state := ts.SuggestedFixAlertStateValid
	refBytes := []byte("refs/heads/main")
	sfa := &ts.SuggestedFixAlert{
		RepositoryID:       alert.RepositoryID,
		LogicalAlertNumber: alert.LogicalAlert.Number,
		SuggestedFix: &ts.SuggestedFix{
			RepositoryID: alert.RepositoryID,
			Description:  "fix description",
		},
		PhysicalAlert:       alert,
		State:               state,
		RefBytes:            refBytes,
		RuleSarifIdentifier: alert.RuleSarifIdentifier,
		RequestedAt:         sqltime.Now(),
	}
	sfa.SetState(state, nil)

	sfa.SuggestedFix.Files = append(sfa.SuggestedFix.Files, &ts.SuggestedFixFile{
		FilePath:     "foo/bar.js",
		DiffContent:  []byte("some_diff"),
		FilePathHash: ts.BuildFilePathHash("foo/bar.js"),
		FileChecksum: ts.BuildFileChecksum([]byte("some content")),
	})
	sfa.SuggestedFix.Files = append(sfa.SuggestedFix.Files, &ts.SuggestedFixFile{
		FilePath:     "foo/baz.js",
		DiffContent:  []byte("s2ome_diff"),
		FilePathHash: ts.BuildFilePathHash("foo/baz.js"),
		FileChecksum: ts.BuildFileChecksum([]byte("some content")),
	})

	sfService := SuggestedFixes{
		DbService:      sfdb,
		AlertService:   alertService,
		LimitsSelector: limits.NewLimitSelector(nil, false),
	}

	err := sfService.CreateSuggestedFixAlert(ctx, sfa)
	require.NoError(t, err)
	require.NotZero(t, sfa.ID)

	actualSFA := &ts.SuggestedFixAlert{}
	err = db.Where("id = ?", sfa.ID).First(actualSFA).Error
	require.NoError(t, err)
	require.Equal(t, alert.LogicalAlert.Number, actualSFA.LogicalAlertNumber)
	require.Equal(t, state, actualSFA.State)
	require.NotNil(t, actualSFA.StateUpdatedAt)

	actualSF := &ts.SuggestedFix{}
	err = db.Where("repository_id = ?", alert.ID).First(actualSF).Error
	require.NoError(t, err)
	require.Equal(t, "fix description", actualSF.Description)

	actualSFFiles := []ts.SuggestedFixFile{}
	err = db.Where("suggested_fix_id = ?", actualSF.ID).Find(&actualSFFiles).Error
	require.NoError(t, err)
	require.Equal(t, 2, len(actualSFFiles))
	require.Equal(t, "foo/bar.js", actualSFFiles[0].FilePath)
	require.Equal(t, "foo/baz.js", actualSFFiles[1].FilePath)

	// test GetSuggestedFix
	sfa, err = sfService.GetSuggestedFixAlert(ctx, actualSFA.ID, nil)
	require.NoError(t, err)
	require.NotNil(t, sfa)
	require.Equal(t, actualSFA.ID, sfa.ID)
}

func TestAlertsToGenerateFixes(t *testing.T) {
	db := dbtest.RequireConnection(t)
	sfdb := suggestedfixes.NewService(db)
	ctx := context.Background()
	commit := ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	refs := [][]byte{[]byte("refs/pull/42/head"), []byte("refs/heads/branch1")}

	repoID := ts.RepositoryEID(1)
	alertNumber := uint32(1)

	alertService := alert.TestService(db)
	sfService := SuggestedFixes{
		DbService:      sfdb,
		AlertService:   alertService,
		LimitsSelector: limits.NewLimitSelector(nil, false),
	}

	// SETUP
	setupAnalysisWithAlerts(t, db, repoID, alertNumber, commit, refs[0])

	findOpts := &ts.FindOptions{
		Preloads: []string{"LogicalAlert", "LogicalAlert.Rule", "LogicalAlert.Rule.Tool", "Analysis", "Analysis.ToolVersion"},
	}

	// Only load the alert requested
	r, err := sfService.PhysicalAlertsByAlertNumbersAndRefs(ctx, repoID, refs, []uint32{alertNumber}, findOpts)
	require.NoError(t, err)
	require.Len(t, r, 1)
	require.NotNil(t, r[0].LogicalAlert)
	require.NotNil(t, r[0].Analysis)
	require.NotNil(t, r[0].Analysis.ToolVersion)
	require.True(t, r[0].Analysis.MostRecent)

	// limit exceeded test
	opts := &ts.FindOptions{
		Preloads:   []string{"LogicalAlert", "LogicalAlert.Rule", "LogicalAlert.Rule.Tool", "Analysis", "Analysis.ToolVersion"},
		Pagination: &ts.Pagination{Limit: 2},
	}
	r, err = sfService.PhysicalAlertsByAlertNumbersAndRefs(ctx, repoID, refs, []uint32{alertNumber, uint32(2), uint32(3)}, opts)
	require.NoError(t, err)
	require.Len(t, r, 2)

	// new analysis with new physical alert
	commit = ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	var tv ts.ToolVersion
	db.Last(&tv)
	analysis := createAnalysis(t, db, repoID, &tv, commit, refs[0])
	var la ts.LogicalAlert
	db.Where("number = ?", alertNumber).Find(&la)
	var p1 ts.PhysicalAlert
	db.Where("logical_alert_id = ?", la.ID).Find(&p1)
	p1.ID = 0
	p1.AnalysisID = analysis.ID
	dbtest.RequireCreate(t, db, &p1)

	r, err = sfService.PhysicalAlertsByAlertNumbersAndRefs(ctx, repoID, refs, []uint32{alertNumber}, findOpts)
	require.NoError(t, err)
	require.NotEmpty(t, r)
	require.Len(t, r, 1)
}

func TestRealGenerateSuggestedFix_NoSFA(t *testing.T) {
	// Setup Service
	db := dbtest.RequireConnection(t)
	sfdb := suggestedfixes.NewService(db)
	alertService := alert.TestService(db)
	archiveService := archiver.NewService(db, store.TestMemoryStore())
	limitsSelector := limits.NewLimitSelector(nil, false)
	spokesStorage := &spokes.MockSpokes{}
	mockGenEmptyFix := NewMockInvalidFixGenerator()
	service := New(sfdb, alertService, archiveService, limitsSelector, spokesStorage, mockGenEmptyFix)

	ctx := context.Background()
	err := service.GenerateSuggestedFix(ctx, ts.SuggestedFixAlertID(1), ts.Sha("commit_sha"), ts.ToolName("CodeQL"), "toolVersion", 1, ts.ThrottlerWorkload_HIGH, false)
	require.ErrorContains(t, err, "record not found")
}

func TestRealGenerateSuggestedFix_SFAIsNotPending(t *testing.T) {
	// Setup Service
	db := dbtest.RequireConnection(t)
	sfdb := suggestedfixes.NewService(db)
	alertService := alert.TestService(db)
	archiveService := archiver.NewService(db, store.TestMemoryStore())
	limitsSelector := limits.NewLimitSelector(nil, false)
	spokesStorage := &spokes.MockSpokes{}
	mockGenEmptyFix := NewMockInvalidFixGenerator()
	service := New(sfdb, alertService, archiveService, limitsSelector, spokesStorage, mockGenEmptyFix)

	ref := "refs/heads/main"
	sfa := &ts.SuggestedFixAlert{
		RefBytes:           []byte(ref),
		LogicalAlertNumber: 1,
		State:              ts.SuggestedFixAlertStateValid,
		StateUpdatedAt:     sqltime.Now(),
		RequestedAt:        sqltime.Now(),
	}
	dbtest.RequireCreate(t, db, sfa)

	ctx := context.Background()
	err := service.GenerateSuggestedFix(ctx, sfa.ID, ts.Sha("commit_sha"), ts.ToolName("CodeQL"), "toolVersion", 1, ts.ThrottlerWorkload_HIGH, false)
	require.NoError(t, err)
	require.Equal(t, mockGenEmptyFix.GenerateFixCallCounter, 0, "should not invoke GenerateFix at all")
}

func TestRealGenerateSuggestedFix_WithInvalidFix(t *testing.T) {
	// Setup Service
	db := dbtest.RequireConnection(t)
	sfdb := suggestedfixes.NewService(db)
	alertService := alert.TestService(db)
	archiveService := archiver.NewService(db, store.TestMemoryStore())
	limitsSelector := limits.NewLimitSelector(nil, false)
	spokesStorage := &spokes.MockSpokes{}
	mockG := NewMockInvalidFixGenerator()
	mockAutofixGenerationCompletedPublisher := &MockAutofixGenerationCompletedPublisher{}
	service := New(sfdb, alertService, archiveService, limitsSelector, spokesStorage, mockG)
	service.AutofixGenerationCompletedPublisher = mockAutofixGenerationCompletedPublisher
	ctx := context.Background()
	commit := ts.Sha("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	refs := [][]byte{[]byte("refs/head/pr")}
	repoID := ts.RepositoryEID(1)
	alertNumber := uint32(42)

	// Create the invalid SFA
	analysis := setupAnalysisWithAlerts(t, db, repoID, alertNumber, commit, refs[0])
	f := analysis.PhysicalAlerts[0].LogicalAlert.FilePath
	require.NotNil(t, f)
	spokesStorage.AddFile(spokes.Filename(f), spokes.CommitOID(commit), []byte("some content"))

	pa := analysis.PhysicalAlerts[0]
	sfa := createPendingSFA(t, db, pa)
	err := service.GenerateSuggestedFix(ctx, sfa.ID, commit, ts.ToToolName("CodeQL"), "1.2.3", 1, ts.ThrottlerWorkload_HIGH, false)
	require.NoError(t, err)
	require.Equal(t, mockG.GenerateFixCallCounter, 1, "should invoke GenerateFix once")

	expectedSFA := &ts.SuggestedFixAlert{}
	require.NoError(t, db.Model(&ts.SuggestedFixAlert{}).Where("id = ?", sfa.ID).First(expectedSFA).Error)
	require.Zero(t, expectedSFA.SuggestedFixID)
	require.Equal(t, ts.SuggestedFixAlertStateInvalid, expectedSFA.State)
}

func TestApplySuggestedFix(t *testing.T) {
	// set up service
	db := dbtest.RequireConnection(t)
	sfdb := suggestedfixes.NewService(db)
	alertService := alert.TestService(db)
	archiveService := archiver.NewService(db, store.TestMemoryStore())
	limitsSelector := limits.NewLimitSelector(nil, false)
	spokesStorage := &spokes.MockSpokes{}
	mockGenEmptyFix := NewMockInvalidFixGenerator()
	service := New(sfdb, alertService, archiveService, limitsSelector, spokesStorage, mockGenEmptyFix)

	ctx := context.Background()

	appliedById := ts.UserEID(1)

	// test inputs
	commit := ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	refs := [][]byte{[]byte("refs/heads/pr")}
	repoID := ts.RepositoryEID(1)
	alertNumber := uint32(1)

	// setup analysis with alerts
	analysis := setupAnalysisWithAlerts(t, db, repoID, alertNumber, commit, refs[0])
	// try with valid rule id
	pa := analysis.PhysicalAlerts[2]
	sfa := &ts.SuggestedFixAlert{
		RepositoryID:       pa.RepositoryID,
		LogicalAlertNumber: pa.LogicalAlert.Number,
		PhysicalAlert:      pa,
		RefBytes:           pa.Analysis.Ref,
		RequestedAt:        sqltime.Now(),
	}
	sfa.SetState(ts.SuggestedFixAlertStateValid, nil)
	dbtest.RequireCreate(t, db, sfa)

	err := service.ApplySuggestedFix(ctx, 1, sfa.LogicalAlertNumber, refs, appliedById)
	require.NoError(t, err)

	logicalNums := []uint32{sfa.LogicalAlertNumber}

	sfas, err := service.GetSuggestedFixAlerts(ctx, 1, logicalNums, refs)
	require.NoError(t, err)
	require.Equal(t, ts.SuggestedFixAlertStateApplied, sfas[0].State)
	require.NotNil(t, sfas[0].StateUpdatedAt)
	require.Equal(t, appliedById, *sfas[0].StateUpdatedActorId)
}

func TestUpdateSFAStateWithNewFix(t *testing.T) {
	// set up service
	db := dbtest.RequireConnection(t)
	sfdb := suggestedfixes.NewService(db)
	alertService := alert.TestService(db)
	archiveService := archiver.NewService(db, store.TestMemoryStore())
	limitsSelector := limits.NewLimitSelector(nil, false)
	spokesStorage := &spokes.MockSpokes{}
	mockGenEmptyFix := NewMockInvalidFixGenerator()
	service := New(sfdb, alertService, archiveService, limitsSelector, spokesStorage, mockGenEmptyFix)

	ctx := context.Background()

	// test inputs
	commit := ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	refs := [][]byte{[]byte("refs/heads/pr")}
	repoID := ts.RepositoryEID(1)
	alertNumber := uint32(1)

	// setup analysis with alerts
	analysis := setupAnalysisWithAlerts(t, db, repoID, alertNumber, commit, refs[0])
	// try with valid rule id
	pa := analysis.PhysicalAlerts[2]
	sfa := &ts.SuggestedFixAlert{
		RepositoryID:       pa.RepositoryID,
		LogicalAlertNumber: pa.LogicalAlert.Number,
		PhysicalAlert:      pa,
		RefBytes:           pa.Analysis.Ref,
		RequestedAt:        sqltime.Now(),
	}
	sfa.SetState(ts.SuggestedFixAlertStateValid, nil)
	dbtest.RequireCreate(t, db, sfa)

	sf := &ts.SuggestedFix{
		RepositoryID: repoID,
		AiVersion:    "test",
		AiModel:      "test",
		Description:  "description",
	}

	err := service.UpdateSFAState(ctx, sfa, ts.SuggestedFixAlertStateValid, nil, sf)
	require.NoError(t, err)

	expected, err := service.GetSuggestedFixAlert(ctx, sfa.ID, nil)
	require.NoError(t, err)
	require.NotNil(t, expected)
	require.Equal(t, ts.SuggestedFixAlertStateValid, expected.State)
	require.NotNil(t, expected.SuggestedFixID)
}

func TestUpdateSFAState(t *testing.T) {
	// set up service
	db := dbtest.RequireConnection(t)
	sfdb := suggestedfixes.NewService(db)
	alertService := alert.TestService(db)
	archiveService := archiver.NewService(db, store.TestMemoryStore())
	limitsSelector := limits.NewLimitSelector(nil, false)
	spokesStorage := &spokes.MockSpokes{}
	mockGenEmptyFix := NewMockInvalidFixGenerator()
	service := New(sfdb, alertService, archiveService, limitsSelector, spokesStorage, mockGenEmptyFix)

	ctx := context.Background()

	// test inputs
	commit := ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	refs := [][]byte{[]byte("refs/heads/pr")}
	repoID := ts.RepositoryEID(1)
	alertNumber := uint32(1)

	// setup analysis with alerts
	analysis := setupAnalysisWithAlerts(t, db, repoID, alertNumber, commit, refs[0])
	// try with valid rule id
	pa := analysis.PhysicalAlerts[2]
	sfa := &ts.SuggestedFixAlert{
		RepositoryID:       pa.RepositoryID,
		LogicalAlertNumber: pa.LogicalAlert.Number,
		PhysicalAlert:      pa,
		RefBytes:           pa.Analysis.Ref,
		RequestedAt:        sqltime.Now(),
	}
	sfa.SetState(ts.SuggestedFixAlertStateValid, nil)
	dbtest.RequireCreate(t, db, sfa)

	err := service.UpdateSFAState(ctx, sfa, ts.SuggestedFixAlertStateInvalid, nil, nil)
	require.NoError(t, err)

	expected, err := service.GetSuggestedFixAlert(ctx, sfa.ID, nil)
	require.NoError(t, err)
	require.Equal(t, ts.SuggestedFixAlertStateInvalid, expected.State)
}

func TestRealGenerateSuggestedFix_NonRetriableError(t *testing.T) {
	// Setup Service
	db := dbtest.RequireConnection(t)
	sfdb := suggestedfixes.NewService(db)
	alertService := alert.TestService(db)
	archiveService := archiver.NewService(db, store.TestMemoryStore())
	limitsSelector := limits.NewLimitSelector(nil, false)
	spokesStorage := &spokes.MockSpokes{}
	mockG := NewMockNonRetriableErrorFixGenerator()
	mockAutofixGenerationCompletedPublisher := &MockAutofixGenerationCompletedPublisher{}
	service := New(sfdb, alertService, archiveService, limitsSelector, spokesStorage, mockG)
	service.AutofixGenerationCompletedPublisher = mockAutofixGenerationCompletedPublisher

	ctx := context.Background()
	commit := ts.Sha("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	refs := [][]byte{[]byte("refs/head/pr")}
	repoID := ts.RepositoryEID(1)
	alertNumber := uint32(42)

	analysis := setupAnalysisWithAlerts(t, db, repoID, alertNumber, commit, refs[0])
	f := analysis.PhysicalAlerts[0].LogicalAlert.FilePath
	require.NotNil(t, f)
	spokesStorage.AddFile(spokes.Filename(f), spokes.CommitOID(commit), []byte("some content"))

	pa := analysis.PhysicalAlerts[0]
	sfa := createPendingSFA(t, db, pa)
	err := service.GenerateSuggestedFix(ctx, sfa.ID, commit, ts.ToToolName("CodeQL"), "1.2.3", 1, ts.ThrottlerWorkload_HIGH, false)
	require.NoError(t, err)
	require.Equal(t, mockG.GenerateFixCallCounter, 1, "should invoke GenerateFix once")

	expectedSFA := &ts.SuggestedFixAlert{}
	require.NoError(t, db.Model(&ts.SuggestedFixAlert{}).Where("id = ?", sfa.ID).First(expectedSFA).Error)
	require.Zero(t, expectedSFA.SuggestedFixID)
	require.Equal(t, ts.SuggestedFixAlertStateError, expectedSFA.State)
}

func TestRealGenerateSuggestedFix_TransientError(t *testing.T) {
	// Setup Service
	db := dbtest.RequireConnection(t)
	sfdb := suggestedfixes.NewService(db)
	alertService := alert.TestService(db)
	archiveService := archiver.NewService(db, store.TestMemoryStore())
	limitsSelector := limits.NewLimitSelector(nil, false)
	spokesStorage := &spokes.MockSpokes{}
	mockG := NewMockTransientErrorFixGenerator()
	service := New(sfdb, alertService, archiveService, limitsSelector, spokesStorage, mockG)

	ctx := context.Background()
	commit := ts.Sha("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	refs := [][]byte{[]byte("refs/head/pr")}
	repoID := ts.RepositoryEID(1)
	alertNumber := uint32(42)

	analysis := setupAnalysisWithAlerts(t, db, repoID, alertNumber, commit, refs[0])
	f := analysis.PhysicalAlerts[0].LogicalAlert.FilePath
	require.NotNil(t, f)
	spokesStorage.AddFile(spokes.Filename(f), spokes.CommitOID(commit), []byte("some content"))

	pa := analysis.PhysicalAlerts[0]
	sfa := createPendingSFA(t, db, pa)
	err := service.GenerateSuggestedFix(ctx, sfa.ID, commit, ts.ToToolName("CodeQL"), "1.2.3", 1, ts.ThrottlerWorkload_HIGH, false)
	require.Error(t, err)
	require.Equal(t, mockG.GenerateFixCallCounter, 1, "should invoke GenerateFix once")

	expectedSFA := &ts.SuggestedFixAlert{}
	require.NoError(t, db.Model(&ts.SuggestedFixAlert{}).Where("id = ?", sfa.ID).First(expectedSFA).Error)
	require.Zero(t, expectedSFA.SuggestedFixID)
	require.Equal(t, ts.SuggestedFixAlertStatePending, expectedSFA.State)
}

func TestCreateSFAsForAlerts(t *testing.T) {
	db := dbtest.RequireConnection(t)
	sfdb := suggestedfixes.NewService(db)
	ctx := context.Background()
	commit := ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	refs := [][]byte{[]byte("refs/heads/pr")}
	requestTime := sqltime.Now()
	repoID := ts.RepositoryEID(1)
	alertNumber := uint32(1)
	spokesStorage := &spokes.MockSpokes{}
	alertService := alert.TestService(db)
	mockGenErrorFix := NewMockErrorFixGenerator()
	sfService := SuggestedFixes{
		DbService:      sfdb,
		AlertService:   alertService,
		SpokesClient:   spokesStorage,
		LimitsSelector: limits.NewLimitSelector(nil, false),
		FixGenerator:   mockGenErrorFix,
	}

	// SETUP
	analysis := setupAnalysisWithAlerts(t, db, repoID, alertNumber, commit, refs[0])

	// create SFAs with not supported rule/language
	res, err := sfService.CreateSFAsForAlerts(ctx, repoID, refs, []uint32{alertNumber}, requestTime)
	require.NoError(t, err)
	require.NotEmpty(t, res)
	require.Len(t, res.PhysicalAlerts, 1)
	require.Len(t, res.GenerateFixForSfaIds, 0)
	// because not supported language was used
	require.Len(t, res.SkippedAlerts, 1)
	require.Len(t, res.SfaExistForAlerts, 0)

	// try with valid rule id
	pa := analysis.PhysicalAlerts[2]

	// create pending SFA
	res, err = sfService.CreateSFAsForAlerts(ctx, repoID, refs, []uint32{pa.LogicalAlert.Number}, requestTime)
	require.NoError(t, err)
	require.NotEmpty(t, res)
	require.Len(t, res.PhysicalAlerts, 1)
	require.Len(t, res.GenerateFixForSfaIds, 1)
	require.Len(t, res.SkippedAlerts, 0)
	require.Len(t, res.SfaExistForAlerts, 0)

	// pending sfa already exists
	res, err = sfService.CreateSFAsForAlerts(ctx, repoID, refs, []uint32{pa.LogicalAlert.Number}, requestTime)
	require.NoError(t, err)
	require.NotEmpty(t, res)
	require.Len(t, res.PhysicalAlerts, 1)
	require.Len(t, res.GenerateFixForSfaIds, 1)
	require.Len(t, res.SkippedAlerts, 0)
	require.Len(t, res.SfaExistForAlerts, 0)
}

func TestCreateSFAsForAlertsErorrStateSameCommit(t *testing.T) {
	// setup infrastructure
	db := dbtest.RequireConnection(t)
	ctx := context.Background()
	sfdb := suggestedfixes.NewService(db)
	requestTime := sqltime.Now()
	alertService := alert.TestService(db)
	sfService := SuggestedFixes{
		DbService:      sfdb,
		AlertService:   alertService,
		LimitsSelector: limits.NewLimitSelector(nil, false),
	}

	// test inputs
	commit := ts.ToSha("da39a3ee5e6b4b0d3255bfef95601890afd80709")
	refs := [][]byte{[]byte("refs/heads/pr")}
	repoID := ts.RepositoryEID(1)
	alertNumber := uint32(1)

	// setup analysis with alerts
	analysis := setupAnalysisWithAlerts(t, db, repoID, alertNumber, commit, refs[0])
	// try with valid rule id
	pa := analysis.PhysicalAlerts[2]

	sfa := &ts.SuggestedFixAlert{
		RepositoryID:       pa.RepositoryID,
		LogicalAlertNumber: pa.LogicalAlert.Number,
		PhysicalAlert:      pa,
		RefBytes:           pa.Analysis.Ref,
		RequestedAt:        requestTime,
	}
	sfa.SetState(ts.SuggestedFixAlertStateError, nil)
	dbtest.RequireCreate(t, db, sfa)

	res, err := sfService.CreateSFAsForAlerts(ctx, repoID, refs, []uint32{pa.LogicalAlert.Number}, requestTime)

	require.NoError(t, err)
	require.Equal(t, 1, len(res.GenerateFixForSfaIds))

	dbtest.RequireCount(t, 2, db.Model(&ts.SuggestedFixAlert{}))
	sfaPending := &ts.SuggestedFixAlert{}
	err = db.Last(sfaPending).Error
	require.NoError(t, err)
	require.Equal(t, ts.SuggestedFixAlertStatePending, sfaPending.State)
	require.NotEqual(t, sfa.ID, sfaPending.ID)
	require.Equal(t, res.GenerateFixForSfaIds[pa.ID], sfaPending.ID)

	sfaError := &ts.SuggestedFixAlert{}
	err = db.Where("id = ?", sfa.ID).First(sfaError).Error
	require.NoError(t, err)
	require.Equal(t, ts.SuggestedFixAlertStateError, sfaError.State)
}

func TestDownloadLimit(t *testing.T) {
	ctx := context.Background()

	s := &spokes.MockSpokes{}
	lt := limits.LimitsDefault()
	lt.SuggestedFixesDownloadFilesLimit = 3
	ls := limits.NewLimitSelector(map[ts.RepositoryEID]limits.Table{
		1: lt,
	}, false)
	sfService := SuggestedFixes{
		SpokesClient:   s,
		LimitsSelector: ls,
	}

	s.AddFile(spokes.Filename("foo.txt"), spokes.CommitOID("beef"), []byte("bar"))

	d := sfService.DownloadFunc(ts.RepositoryEID(1), "beef")
	for i := 0; i < lt.SuggestedFixesDownloadFilesLimit; i++ {
		b, err := d(ctx, "foo.txt")
		require.NoError(t, err)
		require.Equal(t, []byte("bar"), b)
	}
	_, err := d(ctx, "foo.txt")
	require.Error(t, err)
}

func TestIsFixOutdated(t *testing.T) {
	ctx := context.Background()

	s := &spokes.MockSpokes{}
	lt := limits.LimitsDefault()
	ls := limits.NewLimitSelector(map[ts.RepositoryEID]limits.Table{
		1: lt,
	}, false)
	sfService := SuggestedFixes{
		SpokesClient:   s,
		LimitsSelector: ls,
	}

	sf := &ts.SuggestedFix{
		RepositoryID: 1,
		Files: []*ts.SuggestedFixFile{
			{
				FilePath:     "file1",
				FileChecksum: ts.BuildFileChecksum([]byte("file1")),
			},
			{
				FilePath:     "file2",
				FileChecksum: ts.BuildFileChecksum([]byte("file2")),
			},
		},
	}

	commitOID := "commit"
	// Add file1 to spokes
	s.AddFile(spokes.Filename("file1"), spokes.CommitOID(commitOID), []byte("file1"))
	// file2 is missing from spokes

	// returns true if a file is missing
	outdated, err := sfService.IsFixOutdated(ctx, sf, ts.Sha(commitOID))
	require.NoError(t, err)
	require.True(t, outdated)

	// Add file2 with different content
	s.AddFile(spokes.Filename("file2"), spokes.CommitOID(commitOID), []byte("not file 2"))

	// returns true if a file has changed
	outdated, err = sfService.IsFixOutdated(ctx, sf, ts.Sha(commitOID))
	require.NoError(t, err)
	require.True(t, outdated)

	// Add file2 with same content
	s.AddFile(spokes.Filename("file2"), spokes.CommitOID(commitOID), []byte("file2"))

	// returns false if all the files are the same
	outdated, err = sfService.IsFixOutdated(ctx, sf, ts.Sha(commitOID))
	require.NoError(t, err)
	require.False(t, outdated)
}

func createAnalysis(t *testing.T, db *gorm.DB, repoID ts.RepositoryEID, tv *ts.ToolVersion, commit ts.Sha, ref []byte) (analysis *ts.Analysis) {
	t.Helper()
	analysis = &ts.Analysis{
		RepositoryID:       repoID,
		SourceRepositoryID: repoID,
		Ref:                ref,
		CommitOid:          commit,
		ToolID:             tv.ToolID,
		ToolVersionID:      tv.ID,
		ToolVersion:        tv,
		Category:           "js1",
		AnalysisComplete:   true,
		MostRecent:         true,
	}

	db.Model(&ts.Analysis{}).Where("repository_id = ?", repoID).Update("most_recent", false)
	dbtest.RequireCreate(t, db, analysis)

	return
}

func setupAnalysisWithAlerts(t *testing.T, db *gorm.DB, repoID ts.RepositoryEID, alertNumber uint32, commit ts.Sha, ref []byte) (analysis *ts.Analysis) {
	t.Helper()

	tool := &ts.Tool{
		CanonicalName:  "CodeQL",
		GUID:           "e91e0de1-9ce6-4ed3-83ec-16bb54c8000a",
		IsInternalGUID: false,
	}
	dbtest.RequireCreateIgnoreDuplicated(t, db, tool)

	tv := &ts.ToolVersion{
		Version: "1.2.3",
		ToolID:  tool.ID,
	}
	dbtest.RequireCreate(t, db, tv)
	analysis = createAnalysis(t, db, repoID, tv, commit, ref)

	sarifIds := []string{
		"js/one",
		"js/two",
		"js/reflected-xss",
	}

	for i := 0; i < 3; i++ {
		rule1 := &ts.Rule{
			Name:             fmt.Sprintf("Rule %d", i+1),
			ShortDescription: fmt.Sprintf("Rule %d", i+1),
			FullDescription:  fmt.Sprintf("This is Rule %d", i+1),
			SeverityLevel:    ts.SeverityLevelError,
			SarifIdentifier:  sarifIds[i],
			Tool:             tool,
		}
		rule1.SetTags([]string{"rule1"})
		dbtest.RequireCreateIgnoreDuplicated(t, db, rule1)

		n := int(alertNumber) + i
		a1 := &ts.LogicalAlert{
			RuleID:                rule1.ID,
			Rule:                  rule1,
			Number:                uint32(n),
			StableAlertIdentifier: []byte{uint8(n)},
			RepositoryID:          analysis.RepositoryID,
			SarifIdentifier:       rule1.SarifIdentifier,
			Message:               "message",
			FilePath:              "src/file1.js",
		}
		dbtest.RequireCreate(t, db, a1)
		p1 := &ts.PhysicalAlert{
			RuleSarifIdentifier: rule1.SarifIdentifier,
			SeverityLevel:       rule1.SeverityLevel,
			Fingerprint:         "fp1",
			Region: ts.Region{
				StartLine:   1,
				EndLine:     2,
				StartColumn: 1,
				EndColumn:   2,
			},
			LogicalAlertID:        a1.ID,
			LogicalAlert:          a1,
			StableAlertIdentifier: []byte{uint8(n)},
			AnalysisID:            analysis.ID,
			RepositoryID:          analysis.RepositoryID,
			LastStateChangeAt:     sqltime.Now(),
			Analysis:              analysis,
		}
		dbtest.RequireCreate(t, db, p1)

		analysis.PhysicalAlerts = append(analysis.PhysicalAlerts, p1)
	}

	return
}

func createPendingSFA(t *testing.T, db *gorm.DB, pa *ts.PhysicalAlert) *ts.SuggestedFixAlert {
	t.Helper()

	sfa := &ts.SuggestedFixAlert{
		RepositoryID:       pa.RepositoryID,
		LogicalAlertNumber: pa.LogicalAlert.Number,
		PhysicalAlert:      pa,
		RefBytes:           pa.Analysis.Ref,
		RequestedAt:        sqltime.Now(),
	}
	sfa.SetState(ts.SuggestedFixAlertStatePending, nil)

	dbtest.RequireCreate(t, db, sfa)

	return sfa
}

type MockAutofixGenerationCompletedPublisher struct {
	event *tshydro.AutofixGenerationCompleted
}

func (p *MockAutofixGenerationCompletedPublisher) AutofixGenerationCompletedEvent(_ context.Context, event *tshydro.AutofixGenerationCompleted) error {
	p.event = event

	return nil
}
