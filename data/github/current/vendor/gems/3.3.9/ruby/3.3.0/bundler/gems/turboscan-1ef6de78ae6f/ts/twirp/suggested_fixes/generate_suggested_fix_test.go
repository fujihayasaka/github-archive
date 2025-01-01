package suggested_fixes

import (
	"testing"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	tshydro_entities "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0/entities"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestGenerateSuggestedFix_RuleNotSupported(t *testing.T) {
	db, ctx, twirpServ, _, aqMock, mockSuggestedFixesAPI, _ := setupService(t)
	alertNo := uint32(1)
	sfa := setupAlert(t, db, alertNo, "main.js", nil, "rb/some-not-supported-rule", 1)
	var refs [][]byte
	refs = append(refs, sfa.PhysicalAlert.Analysis.Ref)

	req := &proto.GenerateSuggestedFixRequest{
		RepositoryId:  uint64(sfa.RepositoryID),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
	}

	mockSuggestedFixesAPI.EXPECT().SuggestedFixStateChanged(
		gomock.Any(),
		ts.RepositoryEID(req.RepositoryId),
		ts.PullRequestEID(req.PullRequestId),
		req.AlertNumbers,
	).Return(nil)

	res, err := twirpServ.GenerateSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.True(t, res.Success)
	// should only enqueue indexing job
	require.Len(t, aqMock.EnqueuedJobs(), 1)
	indexingJob := aqMock.EnqueuedJobs()[0]
	require.Equal(t, "AlertIndexing", indexingJob.Name())
	require.Equal(t, &sfa.RepositoryID, indexingJob.GetRepositoryID())
	require.Equal(t, req.AlertNumbers, indexingJob.(*jobs.AlertIndexing).LogicalAlertNumbers)
	// should create an sfa
	dbtest.RequireCount(t, 1, db.Model(&ts.SuggestedFixAlert{}))
	sfa = &ts.SuggestedFixAlert{}
	require.NoError(t, db.First(sfa).Error)
	require.Nil(t, sfa.SuggestedFixID)
	require.Equal(t, ts.SuggestedFixAlertStateRuleNotSupported, sfa.State)
}

func TestGenerateSuggestedFix_FixAllQueries(t *testing.T) {
	db, ctx, twirpServ, _, aqMock, mockSuggestedFixesAPI, _ := setupService(t)
	ctx = flipper.WithFeatureEnabled(ctx, flipper.CodeScanningSuggestedFixAllQueries)
	alertNo := uint32(1)
	sfa := setupAlert(t, db, alertNo, "main.js", nil, "rb/some-not-supported-rule", 1)
	var refs [][]byte
	refs = append(refs, sfa.PhysicalAlert.Analysis.Ref)

	req := &proto.GenerateSuggestedFixRequest{
		RepositoryId:  uint64(sfa.RepositoryID),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
	}

	mockSuggestedFixesAPI.EXPECT().SuggestedFixStateChanged(
		gomock.Any(),
		ts.RepositoryEID(req.RepositoryId),
		ts.PullRequestEID(req.PullRequestId),
		req.AlertNumbers,
	).Return(nil)

	res, err := twirpServ.GenerateSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.True(t, res.Success)
	// should enqueue two jobs
	require.Len(t, aqMock.EnqueuedJobs(), 2)
	indexingJob := aqMock.EnqueuedJobs()[1]
	require.Equal(t, "AlertIndexing", indexingJob.Name())
	require.Equal(t, &sfa.RepositoryID, indexingJob.GetRepositoryID())
	require.Equal(t, req.AlertNumbers, indexingJob.(*jobs.AlertIndexing).LogicalAlertNumbers)
	// should create a suggested fix alert with pending state
	dbtest.RequireCount(t, 1, db.Model(&ts.SuggestedFixAlert{}))
	expectedSfa := &ts.SuggestedFixAlert{}
	require.NoError(t, db.First(expectedSfa).Error)
	require.Equal(t, ts.SuggestedFixAlertStatePending, expectedSfa.State)
}

func TestGenerateSuggestedFix_EnqueueJob(t *testing.T) {
	db, ctx, twirpServ, _, aqMock, mockSuggestedFixesAPI, _ := setupService(t)
	alertNo := uint32(1)
	sfa := setupAlert(t, db, alertNo, "main.js", nil, "js/reflected-xss", 1)
	refs := [][]byte{sfa.PhysicalAlert.Analysis.Ref}

	req := &proto.GenerateSuggestedFixRequest{
		RepositoryId:  uint64(sfa.RepositoryID),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
	}

	mockSuggestedFixesAPI.EXPECT().SuggestedFixStateChanged(
		gomock.Any(),
		ts.RepositoryEID(req.RepositoryId),
		ts.PullRequestEID(req.PullRequestId),
		req.AlertNumbers,
	).Return(nil)

	res, err := twirpServ.GenerateSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.True(t, res.Success)

	require.Len(t, aqMock.EnqueuedJobs(), 2)
	job := aqMock.EnqueuedJobs()[0]
	require.Equal(t, "SuggestedFixAlertGenerateHighPriority", job.Name())
	require.Equal(t, &sfa.RepositoryID, job.GetRepositoryID())
	indexingJob := aqMock.EnqueuedJobs()[1]
	require.Equal(t, "AlertIndexing", indexingJob.Name())
	require.Equal(t, &sfa.RepositoryID, indexingJob.GetRepositoryID())
	require.Equal(t, req.AlertNumbers, indexingJob.(*jobs.AlertIndexing).LogicalAlertNumbers)
	// should create an sfa with pending state
	dbtest.RequireCount(t, 1, db.Model(&ts.SuggestedFixAlert{}))
	expectedSfa := &ts.SuggestedFixAlert{}
	require.NoError(t, db.First(expectedSfa).Error)
	require.Equal(t, ts.SuggestedFixAlertStatePending, expectedSfa.State)
}

func TestGenerateSuggestedFix_ValidSfaExists(t *testing.T) {
	db, ctx, twirpServ, mockSpokes, aqMock, mockSuggestedFixesAPI, _ := setupService(t)
	alertNo := uint32(1)
	sfa := setupAlert(t, db, alertNo, "main.js", nil, "js/reflected-xss", 1)
	file_content := []byte("some content")
	sff := sfa.SuggestedFix.Files[0]
	sff.FileChecksum = ts.BuildFileChecksum(file_content)
	dbtest.RequireCreate(t, db, sfa)
	require.NotZero(t, sfa.ID)
	refs := [][]byte{sfa.PhysicalAlert.Analysis.Ref}

	req := &proto.GenerateSuggestedFixRequest{
		RepositoryId:  uint64(sfa.RepositoryID),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
	}

	mockSuggestedFixesAPI.EXPECT().SuggestedFixStateChanged(
		gomock.Any(),
		ts.RepositoryEID(req.RepositoryId),
		ts.PullRequestEID(req.PullRequestId),
		req.AlertNumbers,
	).Return(nil)

	mockSpokes.AddFile(spokes.Filename(sff.FilePath), spokes.CommitOID(sfa.PhysicalAlert.Analysis.CommitOid), file_content)

	// should not enqueue job as valid fix exists, yay cache!
	res, err := twirpServ.GenerateSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.True(t, res.Success)
	// should only enqueue indexing job
	require.Len(t, aqMock.EnqueuedJobs(), 1)
	indexingJob := aqMock.EnqueuedJobs()[0]
	require.Equal(t, "AlertIndexing", indexingJob.Name())
	require.Equal(t, &sfa.RepositoryID, indexingJob.GetRepositoryID())
	require.Equal(t, req.AlertNumbers, indexingJob.(*jobs.AlertIndexing).LogicalAlertNumbers)

	// should not create a new sfa
	dbtest.RequireCount(t, 1, db.Model(&ts.SuggestedFixAlert{}))
	expectedSfa := &ts.SuggestedFixAlert{}
	require.NoError(t, db.First(expectedSfa).Error)
	require.Equal(t, expectedSfa.ID, sfa.ID)
	require.Equal(t, expectedSfa.SuggestedFixID, sfa.SuggestedFixID)
	require.Equal(t, expectedSfa.State, sfa.State)
}

func TestGenerateSuggestedFix_WithPullRequestId(t *testing.T) {
	db, ctx, twirpServ, _, aqMock, mockSuggestedFixesAPI, mockAutofixGeneratePublisher := setupService(t)
	alertNo := uint32(1)
	sfa := setupAlert(t, db, alertNo, "main.js", nil, "js/reflected-xss", 1)

	refs := [][]byte{sfa.PhysicalAlert.Analysis.Ref}

	req := &proto.GenerateSuggestedFixRequest{
		RepositoryId:  uint64(sfa.RepositoryID),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
		PullRequestId: 1,
		Source:        proto.SuggestedFixSource_SUGGESTED_FIX_SOURCE_PR,
	}

	mockSuggestedFixesAPI.EXPECT().SuggestedFixStateChanged(
		gomock.Any(),
		ts.RepositoryEID(req.RepositoryId),
		ts.PullRequestEID(req.PullRequestId),
		req.AlertNumbers,
	).Return(nil)

	res, err := twirpServ.GenerateSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.True(t, res.Success)

	require.Len(t, aqMock.EnqueuedJobs(), 2)
	job := aqMock.EnqueuedJobs()[0]
	require.Equal(t, "SuggestedFixAlertGenerateHighPriority", job.Name())
	require.Equal(t, &sfa.RepositoryID, job.GetRepositoryID())
	indexingJob := aqMock.EnqueuedJobs()[1]
	require.Equal(t, "AlertIndexing", indexingJob.Name())
	require.Equal(t, &sfa.RepositoryID, indexingJob.GetRepositoryID())
	require.Equal(t, req.AlertNumbers, indexingJob.(*jobs.AlertIndexing).LogicalAlertNumbers)

	require.Len(t, mockAutofixGeneratePublisher.events, 1)
	require.Equal(t, &tshydro.AutofixGenerateEvent{
		RepositoryId:       uint64(sfa.RepositoryID),
		LogicalAlertNumber: sfa.LogicalAlertNumber,
		AnalysisRef:        sfa.PhysicalAlert.Analysis.Ref,
		Source:             tshydro_entities.AutofixGenerateEventSource_AUTOFIX_GENERATE_EVENT_SOURCE_PR,
		PullRequestId:      req.PullRequestId,
	}, mockAutofixGeneratePublisher.events[0])
}

func TestGenerateSuggestedFix_ForCampaign(t *testing.T) {
	db, ctx, twirpServ, _, aqMock, mockSuggestedFixesAPI, mockAutofixGeneratePublisher := setupService(t)

	alert1No := uint32(1)
	alert2No := uint32(100)
	alertNumbers := []uint32{alert1No, alert2No}
	repoId := ts.RepositoryEID(1)
	sfas := setupAlerts(t, db, alertNumbers, "main.js", nil, "js/reflected-xss", repoId)

	ref := sfas[0].PhysicalAlert.Analysis.Ref

	req := &proto.GenerateSuggestedFixRequest{
		RepositoryId:  uint64(repoId),
		AlertNumbers:  alertNumbers,
		RefNamesBytes: [][]byte{ref},
		Source:        proto.SuggestedFixSource_SUGGESTED_FIX_SOURCE_SECURITY_CAMPAIGN,
	}

	mockSuggestedFixesAPI.EXPECT().SuggestedFixStateChanged(
		gomock.Any(),
		ts.RepositoryEID(req.RepositoryId),
		ts.PullRequestEID(0),
		req.AlertNumbers,
	).Return(nil)

	res, err := twirpServ.GenerateSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.True(t, res.Success)

	require.Len(t, aqMock.EnqueuedJobs(), 3)
	generationJob1 := aqMock.EnqueuedJobs()[0]
	require.Equal(t, "SuggestedFixAlertGenerateLowPriority", generationJob1.Name())
	require.Equal(t, &repoId, generationJob1.GetRepositoryID())
	generationJob2 := aqMock.EnqueuedJobs()[1]
	require.Equal(t, "SuggestedFixAlertGenerateLowPriority", generationJob2.Name())
	require.Equal(t, &repoId, generationJob2.GetRepositoryID())
	indexingJob := aqMock.EnqueuedJobs()[2]
	require.Equal(t, "AlertIndexing", indexingJob.Name())
	require.Equal(t, &repoId, indexingJob.GetRepositoryID())
	require.Equal(t, req.AlertNumbers, indexingJob.(*jobs.AlertIndexing).LogicalAlertNumbers)

	require.Len(t, mockAutofixGeneratePublisher.events, 2)
	require.Equal(t, &tshydro.AutofixGenerateEvent{
		RepositoryId:       uint64(repoId),
		LogicalAlertNumber: alert1No,
		AnalysisRef:        ref,
		Source:             tshydro_entities.AutofixGenerateEventSource_AUTOFIX_GENERATE_EVENT_SOURCE_SECURITY_CAMPAIGN,
		PullRequestId:      req.PullRequestId,
	}, mockAutofixGeneratePublisher.events[0])
	require.Equal(t, &tshydro.AutofixGenerateEvent{
		RepositoryId:       uint64(repoId),
		LogicalAlertNumber: alert2No,
		AnalysisRef:        ref,
		Source:             tshydro_entities.AutofixGenerateEventSource_AUTOFIX_GENERATE_EVENT_SOURCE_SECURITY_CAMPAIGN,
		PullRequestId:      req.PullRequestId,
	}, mockAutofixGeneratePublisher.events[1])
}

func TestGenerateSuggestedFix_ForOndemandApi(t *testing.T) {
	db, ctx, twirpServ, _, aqMock, mockSuggestedFixesAPI, _ := setupService(t)
	alertNo := uint32(1)
	sfa := setupAlert(t, db, alertNo, "main.js", nil, "js/reflected-xss", 1)
	refs := [][]byte{sfa.PhysicalAlert.Analysis.Ref}

	req := &proto.GenerateSuggestedFixRequest{
		RepositoryId:  uint64(sfa.RepositoryID),
		AlertNumbers:  []uint32{sfa.LogicalAlertNumber},
		RefNamesBytes: refs,
		Source:        proto.SuggestedFixSource_SUGGESTED_FIX_SOURCE_ONDEMAND_API,
	}

	mockSuggestedFixesAPI.EXPECT().SuggestedFixStateChanged(
		gomock.Any(),
		ts.RepositoryEID(req.RepositoryId),
		ts.PullRequestEID(req.PullRequestId),
		req.AlertNumbers,
	).Return(nil)

	res, err := twirpServ.GenerateSuggestedFix(ctx, req)
	require.NoError(t, err)
	require.True(t, res.Success)

	require.Len(t, aqMock.EnqueuedJobs(), 2)
	job := aqMock.EnqueuedJobs()[0]
	require.Equal(t, "SuggestedFixAlertGenerateLowPriority", job.Name())
	require.Equal(t, &sfa.RepositoryID, job.GetRepositoryID())
	indexingJob := aqMock.EnqueuedJobs()[1]
	require.Equal(t, "AlertIndexing", indexingJob.Name())
	require.Equal(t, &sfa.RepositoryID, indexingJob.GetRepositoryID())
	require.Equal(t, req.AlertNumbers, indexingJob.(*jobs.AlertIndexing).LogicalAlertNumbers)
	// should create an sfa with pending state
	dbtest.RequireCount(t, 1, db.Model(&ts.SuggestedFixAlert{}))
	expectedSfa := &ts.SuggestedFixAlert{}
	require.NoError(t, db.First(expectedSfa).Error)
	require.Equal(t, ts.SuggestedFixAlertStatePending, expectedSfa.State)
}
