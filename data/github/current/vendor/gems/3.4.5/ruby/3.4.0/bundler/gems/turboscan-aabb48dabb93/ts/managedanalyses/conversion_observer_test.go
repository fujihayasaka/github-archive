package managedanalyses_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/github/turboscan/ts/appctx"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/managedanalyses"
	"github.com/github/turboscan/ts/mocks"
	"github.com/pkg/errors"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"
)

func TestObserveConversionBetween_NoConversion(t *testing.T) {
	ctx := context.Background()

	mockCtrl := gomock.NewController(t)
	logger := mocks.NewMockLogger(mockCtrl)
	ctx = appctx.WithLogger(ctx, logger)

	// Repo with no conversion
	repoID := ts.RepositoryEID(1)

	co := managedanalyses.NewConversionObserver(mockDisabledBetween(repoID), mockLatestAnalysesFor(repoID), nil)

	// repo 1 should log that no conversion try was found
	logger.EXPECT().Info("repo didn't try to convert to advanced setup", repoID.AsKVP())

	err := co.ObserveConversionBetween(ctx, time.Now().Add(time.Hour*-24), time.Now().Add(time.Hour*-23))
	require.NoError(t, err)
}

func TestObserveConversionBetween_SuccessfulAndFailedConvesion(t *testing.T) {
	ctx := context.Background()

	mockCtrl := gomock.NewController(t)
	logger := mocks.NewMockLogger(mockCtrl)
	ctx = appctx.WithLogger(ctx, logger)

	// Repo with 1 successful and 1 failed conversion
	repoID := ts.RepositoryEID(2)
	a1 := &ts.Analysis{}
	a2 := &ts.Analysis{Failed: true}

	co := managedanalyses.NewConversionObserver(mockDisabledBetween(repoID), mockLatestAnalysesFor(repoID, a1, a2), mockFetchFile(repoID))

	// repo 2 should log 2 conversions, 1 successful, 1 failed
	logger.EXPECT().Info("conversion observed for repo",
		repoID.AsKVP(),
		kvp.String("gh.turboscan.conversion_observer.status", "COMPLETE"),
		kvp.String("gh.turboscan.conversion_observer.category", "category0"),
		kvp.String("gh.turboscan.conversion_observer.workflow_path", "repo2/category0"),
		kvp.String("gh.turboscan.conversion_observer.workflow", "workflow file"),
	)
	logger.EXPECT().Info("conversion observed for repo",
		repoID.AsKVP(),
		kvp.String("gh.turboscan.conversion_observer.status", "FAILED"),
		kvp.String("gh.turboscan.conversion_observer.category", "category1"),
		kvp.String("gh.turboscan.conversion_observer.workflow_path", "repo2/category1"),
		kvp.String("gh.turboscan.conversion_observer.workflow", "workflow file"),
	)

	err := co.ObserveConversionBetween(ctx, time.Now().Add(time.Hour*-24), time.Now().Add(time.Hour*-23))
	require.NoError(t, err)
}

func TestObserveConversionBetween_BeforeDisablingDefaultSetup(t *testing.T) {
	ctx := context.Background()

	mockCtrl := gomock.NewController(t)
	logger := mocks.NewMockLogger(mockCtrl)
	ctx = appctx.WithLogger(ctx, logger)

	// Repo with 1 advanced setup analysis created before disabling default setup, so it is not a conversion
	repoID := ts.RepositoryEID(3)
	a := &ts.Analysis{
		BaseModel: ts.BaseModel{CreatedAt: sqltime.Time{Time: time.Now().Add(time.Hour * -48)}},
	}

	co := managedanalyses.NewConversionObserver(mockDisabledBetween(repoID), mockLatestAnalysesFor(repoID, a), nil)

	// repo 3 should log that no conversion try was found
	logger.EXPECT().Info("repo didn't try to convert to advanced setup", repoID.AsKVP())

	err := co.ObserveConversionBetween(ctx, time.Now().Add(time.Hour*-24), time.Now().Add(time.Hour*-23))
	require.NoError(t, err)
}

func TestObserveConversionBetween_FailWorkflowFetch(t *testing.T) {
	ctx := context.Background()

	mockCtrl := gomock.NewController(t)
	logger := mocks.NewMockLogger(mockCtrl)
	ctx = appctx.WithLogger(ctx, logger)

	// Repo with 1 successful conversion that fails to fetch the workflow file
	repoID := ts.RepositoryEID(4)
	fetchFileErr := errors.New("Failed to fetch file")
	fetchFile := func(ctx context.Context, repoID ts.RepositoryEID, path string, sha ts.Sha) ([]byte, error) {
		return nil, fetchFileErr
	}

	co := managedanalyses.NewConversionObserver(mockDisabledBetween(repoID), mockLatestAnalysesFor(repoID, &ts.Analysis{CommitOid: "aaaa"}), fetchFile)

	// repo 4 should log an error for fetching the file, and a conversion log
	logger.EXPECT().WithError(fetchFileErr).Return(logger)
	logger.EXPECT().Error("failed to get the workflow file",
		repoID.AsKVP(),
		kvp.String("gh.turboscan.conversion_observer.workflow_path", "repo4/category0"),
		kvp.String("gh.turboscan.conversion_observer.commit_oid", "aaaa"),
	)
	logger.EXPECT().Info("conversion observed for repo",
		repoID.AsKVP(),
		kvp.String("gh.turboscan.conversion_observer.status", "COMPLETE"),
		kvp.String("gh.turboscan.conversion_observer.category", "category0"),
		kvp.String("gh.turboscan.conversion_observer.workflow_path", "repo4/category0"),
		kvp.String("gh.turboscan.conversion_observer.workflow", ""),
	)

	err := co.ObserveConversionBetween(ctx, time.Now().Add(time.Hour*-24), time.Now().Add(time.Hour*-23))
	require.NoError(t, err)
}

func mockLatestAnalysesFor(targetRepoID ts.RepositoryEID, as ...*ts.Analysis) func(context.Context, ts.RepositoryEID) ([]*ts.Analysis, error) {
	analyses := []*ts.Analysis{}
	// Set shared fields for all analyses
	for idx, a := range as {
		b := *a
		b.RepositoryID = targetRepoID
		b.AnalysisComplete = true
		b.Category = ts.Category(fmt.Sprintf("category%d", idx))
		b.WorkflowPath = ts.WorkflowPath(fmt.Sprintf("repo%d/%s", targetRepoID, b.Category))
		if b.CreatedAt.IsZero() {
			b.CreatedAt = sqltime.Now()
		}
		analyses = append(analyses, &b)
	}

	return func(ctx context.Context, repoID ts.RepositoryEID) ([]*ts.Analysis, error) {
		if targetRepoID != repoID {
			return nil, errors.New("invalid repoID")
		}
		return analyses, nil
	}
}

func mockDisabledBetween(repos ...ts.RepositoryEID) func(context.Context, time.Time, time.Time) ([]ts.DisabledCodeqlRepo, error) {
	disabledAtTime := sqltime.Time{Time: time.Now().Add(time.Hour * -2)}
	out := []ts.DisabledCodeqlRepo{}
	for _, r := range repos {
		out = append(out, ts.DisabledCodeqlRepo{RepositoryID: r, DisabledAt: disabledAtTime})
	}
	return func(context.Context, time.Time, time.Time) ([]ts.DisabledCodeqlRepo, error) {
		return out, nil
	}
}

func mockFetchFile(targetRepo ts.RepositoryEID) func(context.Context, ts.RepositoryEID, string, ts.Sha) ([]byte, error) {
	return func(ctx context.Context, repoID ts.RepositoryEID, _ string, _ ts.Sha) ([]byte, error) {
		if targetRepo != repoID {
			return nil, errors.New("invalid repoID")
		}
		return []byte("workflow file"), nil
	}
}
