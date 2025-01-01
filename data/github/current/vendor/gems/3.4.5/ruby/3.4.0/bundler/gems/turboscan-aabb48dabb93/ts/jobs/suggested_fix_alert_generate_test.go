package jobs

import (
	"context"
	"testing"

	"github.com/SamuelTissot/sqltime"
	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/cocofix"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/limits"
	"github.com/github/turboscan/ts/mocks"
	asdb "github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/archiver"
	sfdb "github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/sarif/store"
	sf "github.com/github/turboscan/ts/suggestedfixes"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
	"github.com/jinzhu/gorm"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestPerformSuggestedFixAlertGenerate_RetriesOnTransientError(t *testing.T) {
	// Setup environment
	ctx := context.Background()
	db := dbtest.RequireConnection(t)

	sfDB := sfdb.NewService(db)
	asDB := asdb.TestService(db)
	arch := archiver.NewService(db, store.TestMemoryStore())

	ls := limits.TestLimitSelector()
	mockSpokes := &spokes.MockSpokes{}
	mockAutofixGenerationCompletedPublisher := &MockAutofixGenerationCompletedPublisher{}
	sfServ := sf.New(sfDB, asDB, arch, ls, mockSpokes, sf.NewMockTransientErrorFixGenerator())
	sfServ.AutofixGenerationCompletedPublisher = mockAutofixGenerationCompletedPublisher

	mockCtrl := gomock.NewController(t)
	mockSuggestedFixesAPI := mocks.NewMockSuggestedFixesAPI(mockCtrl)
	sfServ.GitHubTwirpApiClient = mockSuggestedFixesAPI

	aqueductMock := &aqueduct.AqueductMock{}
	s := &aqueduct.TSServices{
		SuggestedFixes: sfServ,
		Aqueduct:       aqueductMock,
	}

	sfServ.SyncUpdate = func(ctx context.Context, reason string, payload map[string]string, repoID ts.RepositoryEID, prID ts.PullRequestEID, alertNumbers ...uint32) {
		_ = sfServ.GitHubTwirpApiClient.SuggestedFixStateChanged(ctx, repoID, prID, alertNumbers)

		_, _ = aqueductMock.PerformLater(ctx, &AlertIndexing{
			Context:             reason,
			RepositoryID:        repoID,
			LogicalAlertNumbers: alertNumbers,
		})
	}

	// Create pending SFA
	alertNo := uint32(1)
	sfa := setupAlerts(t, db, alertNo, "main.js", nil, "js/reflected-xss", ts.SuggestedFixAlertStatePending, 1)
	dbtest.RequireCreate(t, db, sfa)

	// Setup the job
	job := SuggestedFixAlertGenerate{
		RepoID:              sfa.RepositoryID,
		CommitOid:           sfa.PhysicalAlert.Analysis.CommitOid,
		ToolVersion:         sfa.PhysicalAlert.Analysis.ToolVersion.Version,
		ToolName:            sfa.PhysicalAlert.Analysis.ToolVersion.Name.String(),
		SuggestedFixAlertID: sfa.ID,
	}

	err := PerformSuggestedFixAlertGenerate(ctx, s, job, ts.ThrottlerWorkload_HIGH)
	require.Error(t, err) // If the Perform returns an error, the aqueduct worker will retry the job
	require.True(t, cocofix.IsTransientError(err))

	// Check that sfa stays pending
	var outSfa ts.SuggestedFixAlert
	db.First(&outSfa)
	require.Equal(t, ts.SuggestedFixAlertStatePending, outSfa.State)

	// Test that the job marks the sfa as error if the last retry fails
	// This should also publish the state change to the API and ES
	mockSuggestedFixesAPI.EXPECT().SuggestedFixStateChanged(
		gomock.Any(),
		job.RepoID,
		job.PullRequestID,
		[]uint32{alertNo},
	).Return(nil)

	newCtx := appctx.WithAqueductJobRetryCount(ctx, aqueduct.MaxRetryCount)
	err = PerformSuggestedFixAlertGenerate(newCtx, s, job, ts.ThrottlerWorkload_HIGH)
	require.Error(t, err) // The perform should still return the error
	db.First(&outSfa)
	require.Equal(t, ts.SuggestedFixAlertStateError, outSfa.State)

	// The indexing job should have been enqueued
	require.Len(t, aqueductMock.EnqueuedJobs(), 1)
	indexingJob, isOk := aqueductMock.EnqueuedJobs()[0].(*AlertIndexing)
	require.True(t, isOk)
	require.Equal(t, sfa.RepositoryID, indexingJob.RepositoryID)
	require.Equal(t, []uint32{alertNo}, indexingJob.LogicalAlertNumbers)
}

func TestSuggestedFixAlertGenerate_perform_valid_fix(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	sfDB := sfdb.NewService(db)
	ls := limits.TestLimitSelector()
	as := asdb.TestService(db)
	arch := archiver.NewService(db, store.TestMemoryStore())
	mockSpokes := &spokes.MockSpokes{}
	sfServ := sf.New(sfDB, as, arch, ls, mockSpokes, sf.NewMockValidFixGenerator())
	mockCtrl := gomock.NewController(t)
	mockSuggestedFixesAPI := mocks.NewMockSuggestedFixesAPI(mockCtrl)
	mockAutofixGenerationCompletedPublisher := &MockAutofixGenerationCompletedPublisher{}
	sfServ.GitHubTwirpApiClient = mockSuggestedFixesAPI
	sfServ.AutofixGenerationCompletedPublisher = mockAutofixGenerationCompletedPublisher

	aqueductMock := &aqueduct.AqueductMock{}
	s := &aqueduct.TSServices{
		SuggestedFixes: sfServ,
		Aqueduct:       aqueductMock,
	}

	sfServ.SyncUpdate = func(ctx context.Context, reason string, payload map[string]string, repoID ts.RepositoryEID, prID ts.PullRequestEID, alertNumbers ...uint32) {
		_ = sfServ.GitHubTwirpApiClient.SuggestedFixStateChanged(ctx, repoID, prID, alertNumbers)

		_, _ = aqueductMock.PerformLater(ctx, &AlertIndexing{
			Context:             reason,
			RepositoryID:        repoID,
			LogicalAlertNumbers: alertNumbers,
		})
	}

	alertNo := uint32(1)
	sfa := setupAlerts(t, db, alertNo, "main.js", nil, "js/reflected-xss", ts.SuggestedFixAlertStatePending, 1)
	dbtest.RequireCreate(t, db, sfa)

	f := sfa.PhysicalAlert.LogicalAlert.FilePath
	require.NotNil(t, f)
	mockSpokes.AddFile(spokes.Filename(f), spokes.CommitOID(sfa.PhysicalAlert.Analysis.CommitOid), []byte("some content"))

	job := SuggestedFixAlertGenerate{
		RepoID:              sfa.RepositoryID,
		CommitOid:           sfa.PhysicalAlert.Analysis.CommitOid,
		ToolVersion:         sfa.PhysicalAlert.Analysis.ToolVersion.Version,
		ToolName:            sfa.PhysicalAlert.Analysis.ToolVersion.Name.String(),
		SuggestedFixAlertID: sfa.ID,
	}

	mockSuggestedFixesAPI.EXPECT().SuggestedFixStateChanged(
		gomock.Any(),
		job.RepoID,
		job.PullRequestID,
		[]uint32{alertNo},
	).Return(nil)

	err := PerformSuggestedFixAlertGenerate(ctx, s, job, ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)

	dbtest.RequireCount(t, 1, db.Model(&ts.SuggestedFixAlert{}))
	expected := &ts.SuggestedFixAlert{}
	require.NoError(t, db.First(expected).Error)
	require.Equal(t, ts.SuggestedFixAlertStateValid, expected.State)
	require.NotZero(t, expected.SuggestedFixID)

	// Assert that the indexing job was also enqueued as expected
	require.Len(t, aqueductMock.EnqueuedJobs(), 1)
	indexingJob, isOk := aqueductMock.EnqueuedJobs()[0].(*AlertIndexing)
	require.True(t, isOk)
	require.Equal(t, sfa.RepositoryID, indexingJob.RepositoryID)
	require.Equal(t, []uint32{alertNo}, indexingJob.LogicalAlertNumbers)
}

func TestSuggestedFixAlertGenerate_perform_invalid_fix(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	sfDB := sfdb.NewService(db)
	ls := limits.TestLimitSelector()
	as := asdb.TestService(db)
	arch := archiver.NewService(db, store.TestMemoryStore())
	mockSpokes := &spokes.MockSpokes{}
	mockAutofixGenerationCompletedPublisher := &MockAutofixGenerationCompletedPublisher{}
	sfServ := sf.New(sfDB, as, arch, ls, mockSpokes, sf.NewMockInvalidFixGenerator())
	sfServ.AutofixGenerationCompletedPublisher = mockAutofixGenerationCompletedPublisher
	mockCtrl := gomock.NewController(t)
	mockSuggestedFixesAPI := mocks.NewMockSuggestedFixesAPI(mockCtrl)
	sfServ.GitHubTwirpApiClient = mockSuggestedFixesAPI
	aqueductMock := &aqueduct.AqueductMock{}
	s := &aqueduct.TSServices{
		SuggestedFixes: sfServ,
		Aqueduct:       aqueductMock,
	}

	sfServ.SyncUpdate = func(ctx context.Context, reason string, payload map[string]string, repoID ts.RepositoryEID, prID ts.PullRequestEID, alertNumbers ...uint32) {
		_ = sfServ.GitHubTwirpApiClient.SuggestedFixStateChanged(ctx, repoID, prID, alertNumbers)

		_, _ = aqueductMock.PerformLater(ctx, &AlertIndexing{
			Context:             reason,
			RepositoryID:        repoID,
			LogicalAlertNumbers: alertNumbers,
		})
	}

	alertNo := uint32(1)
	sfa := setupAlerts(t, db, alertNo, "main.js", nil, "js/reflected-xss", ts.SuggestedFixAlertStatePending, 1)
	dbtest.RequireCreate(t, db, sfa)

	f := sfa.PhysicalAlert.LogicalAlert.FilePath
	require.NotNil(t, f)
	mockSpokes.AddFile(spokes.Filename(f), spokes.CommitOID(sfa.PhysicalAlert.Analysis.CommitOid), []byte("some content"))

	job := SuggestedFixAlertGenerate{
		RepoID:              sfa.RepositoryID,
		CommitOid:           sfa.PhysicalAlert.Analysis.CommitOid,
		ToolVersion:         sfa.PhysicalAlert.Analysis.ToolVersion.Version,
		ToolName:            sfa.PhysicalAlert.Analysis.ToolVersion.Name.String(),
		SuggestedFixAlertID: sfa.ID,
	}

	mockSuggestedFixesAPI.EXPECT().SuggestedFixStateChanged(
		gomock.Any(),
		job.RepoID,
		job.PullRequestID,
		[]uint32{alertNo},
	).Return(nil)

	err := PerformSuggestedFixAlertGenerate(ctx, s, job, ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)

	dbtest.RequireCount(t, 1, db.Model(&ts.SuggestedFixAlert{}))
	expected := &ts.SuggestedFixAlert{}
	require.NoError(t, db.First(expected).Error)
	require.Equal(t, ts.SuggestedFixAlertStateInvalid, expected.State)
	require.Zero(t, expected.SuggestedFixID)
}

func TestSuggestedFixAlertGenerate_perform_noop(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	s := sfdb.NewService(db)
	ls := limits.TestLimitSelector()
	as := asdb.TestService(db)
	arch := archiver.NewService(db, store.TestMemoryStore())
	mockSpokes := &spokes.MockSpokes{}
	sfServ := sf.New(s, as, arch, ls, mockSpokes, &sf.MockFixGenerator{})

	alertNo := uint32(1)
	sfa := setupAlerts(t, db, alertNo, "main.js", nil, "js/reflected-xss", ts.SuggestedFixAlertStateValid, 1)
	dbtest.RequireCreate(t, db, sfa)
	require.NotZero(t, sfa.ID)

	job := &SuggestedFixAlertGenerate{
		RepoID:              sfa.RepositoryID,
		CommitOid:           sfa.PhysicalAlert.Analysis.CommitOid,
		ToolVersion:         sfa.PhysicalAlert.Analysis.ToolVersion.Version,
		ToolName:            sfa.PhysicalAlert.Analysis.ToolVersion.Name.String(),
		SuggestedFixAlertID: sfa.ID,
	}
	err := job.perform(ctx, sfServ, ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)

	// should not create any new sfa as sfa already created earlier
	dbtest.RequireCount(t, 1, db.Model(&ts.SuggestedFixAlert{}))
	expected := &ts.SuggestedFixAlert{}
	require.NoError(t, db.First(expected).Error)
	require.Equal(t, ts.SuggestedFixAlertStateValid, expected.State)
	require.NotZero(t, expected.SuggestedFixID)
}

func TestSuggestedFixAlertGenerate_WithPullRequestId(t *testing.T) {
	ctx := context.Background()
	db := dbtest.RequireConnection(t)
	sfDB := sfdb.NewService(db)
	ls := limits.TestLimitSelector()
	as := asdb.TestService(db)
	arch := archiver.NewService(db, store.TestMemoryStore())
	mockSpokes := &spokes.MockSpokes{}
	mockG := sf.NewMockValidFixGenerator()
	sfServ := sf.New(sfDB, as, arch, ls, mockSpokes, mockG)
	mockCtrl := gomock.NewController(t)
	mockSuggestedFixesAPI := mocks.NewMockSuggestedFixesAPI(mockCtrl)
	mockAutofixGenerationCompletedPublisher := &MockAutofixGenerationCompletedPublisher{}
	sfServ.GitHubTwirpApiClient = mockSuggestedFixesAPI
	sfServ.AutofixGenerationCompletedPublisher = mockAutofixGenerationCompletedPublisher
	aqueductMock := &aqueduct.AqueductMock{}
	s := &aqueduct.TSServices{
		SuggestedFixes: sfServ,
		Aqueduct:       aqueductMock,
	}

	sfServ.SyncUpdate = func(ctx context.Context, reason string, payload map[string]string, repoID ts.RepositoryEID, prID ts.PullRequestEID, alertNumbers ...uint32) {
		_ = sfServ.GitHubTwirpApiClient.SuggestedFixStateChanged(ctx, repoID, prID, alertNumbers)

		_, _ = aqueductMock.PerformLater(ctx, &AlertIndexing{
			Context:             reason,
			RepositoryID:        repoID,
			LogicalAlertNumbers: alertNumbers,
		})
	}

	alertNo := uint32(1)
	sfa := setupAlerts(t, db, alertNo, "main.js", nil, "js/reflected-xss", ts.SuggestedFixAlertStatePending, 1)
	dbtest.RequireCreate(t, db, sfa)

	f := sfa.PhysicalAlert.LogicalAlert.FilePath
	require.NotNil(t, f)
	mockSpokes.AddFile(spokes.Filename(f), spokes.CommitOID(sfa.PhysicalAlert.Analysis.CommitOid), []byte("some content"))

	job := SuggestedFixAlertGenerate{
		RepoID:              sfa.RepositoryID,
		CommitOid:           sfa.PhysicalAlert.Analysis.CommitOid,
		ToolVersion:         sfa.PhysicalAlert.Analysis.ToolVersion.Version,
		ToolName:            sfa.PhysicalAlert.Analysis.ToolVersion.Name.String(),
		SuggestedFixAlertID: sfa.ID,
		PullRequestID:       1,
	}

	mockSuggestedFixesAPI.EXPECT().SuggestedFixStateChanged(
		gomock.Any(),
		job.RepoID,
		job.PullRequestID,
		[]uint32{alertNo},
	).Return(nil)

	err := PerformSuggestedFixAlertGenerate(ctx, s, job, ts.ThrottlerWorkload_HIGH)
	require.NoError(t, err)

	dbtest.RequireCount(t, 1, db.Model(&ts.SuggestedFixAlert{}))
	expected := &ts.SuggestedFixAlert{}
	require.NoError(t, db.First(expected).Error)
	require.Equal(t, ts.SuggestedFixAlertStateValid, expected.State)
	require.NotZero(t, expected.SuggestedFixID)
}

func setupAlerts(t *testing.T, db *gorm.DB, number uint32, filePath string, analysis *ts.Analysis, sarifId string, state ts.SuggestedFixAlertState, repoId ts.RepositoryEID) *ts.SuggestedFixAlert {
	t.Helper()
	if analysis == nil {
		tool := &ts.Tool{CanonicalName: "CodeQL"}
		require.NoError(t, db.FirstOrCreate(tool, tool).Error)
		tv := &ts.ToolVersion{Name: ts.ToolName("CodeQL"), ToolID: tool.ID, SemanticVersion: "2.0.1"}
		dbtest.RequireCreate(t, db, tv)
		analysis = &ts.Analysis{
			CommitOid:          "xxx",
			Ref:                []byte("refs/heads/ref1"),
			RepositoryID:       repoId,
			SourceRepositoryID: repoId,
			MostRecent:         true,
			AnalysisComplete:   true,
			Tool:               tool,
			ToolVersion:        tv,
		}
		dbtest.RequireCreate(t, db, analysis)
	}

	rule := &ts.Rule{
		SarifIdentifier: sarifId,
		Tool:            analysis.Tool,
	}
	dbtest.RequireCreate(t, db, rule)

	la := &ts.LogicalAlert{
		Number:                number,
		RepositoryID:          repoId,
		StableAlertIdentifier: []byte(filePath),
		SarifIdentifier:       sarifId,
		RuleID:                rule.ID,
		FilePath:              filePath,
	}
	dbtest.RequireCreate(t, db, la)
	actual := &ts.LogicalAlert{}
	db.Where("number = ?", la.Number).First(actual)
	require.Equal(t, la.Number, actual.Number)

	now := sqltime.Now()
	pa := &ts.PhysicalAlert{
		RepositoryID:          repoId,
		AnalysisID:            analysis.ID,
		LogicalAlertID:        la.ID,
		StableAlertIdentifier: []byte(filePath),
		LastStateChangeAt:     now,
	}
	require.NoError(t, db.Create(pa).Error)

	pa.LogicalAlert = la
	pa.Analysis = analysis

	stateTime := sqltime.Now()
	sfa := &ts.SuggestedFixAlert{
		RepositoryID:        repoId,
		LogicalAlertNumber:  la.Number,
		State:               state,
		StateUpdatedAt:      stateTime,
		RuleSarifIdentifier: la.SarifIdentifier,
		PhysicalAlert:       pa,
		RefBytes:            analysis.Ref,
		RequestedAt:         stateTime,
	}

	if state == ts.SuggestedFixAlertStateValid {
		sf := &ts.SuggestedFix{
			RepositoryID: repoId,
			Description:  "test",
			AiVersion:    "test",
			AiModel:      "test",
		}

		files := []*ts.SuggestedFixFile{
			{
				RepositoryID: repoId,
				FilePath:     filePath,
				FileChecksum: ts.BuildFileChecksum([]byte("beef")),
				DiffContent:  []byte("test"),
			},
		}

		sf.Files = files
		sfa.SuggestedFix = sf
	}

	return sfa
}

type MockAutofixGenerationCompletedPublisher struct {
	event *tshydro.AutofixGenerationCompleted
}

func (p *MockAutofixGenerationCompletedPublisher) AutofixGenerationCompletedEvent(_ context.Context, event *tshydro.AutofixGenerationCompleted) error {
	p.event = event

	return nil
}
