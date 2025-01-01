package root

import (
	"context"
	"io"
	"os"
	"testing"

	"github.com/github/turboscan/ts/appctx"

	"github.com/pkg/errors"

	"go.uber.org/mock/gomock"

	"github.com/github/github-telemetry-go/log"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/mocks"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/stretchr/testify/require"
)

func setup(t *testing.T, w *os.File, args arguments) (context.Context, *mocks.MockRepoDeleter, *mocks.MockRepoCleanup, *RepoDeleterCmd) {
	t.Helper()

	logger, _ := log.NewFromEnv(log.WithWriteSyncer(w))

	ctx := appctx.WithLogger(context.Background(), logger)

	mockCtrl := gomock.NewController(t)
	mockService := mocks.NewMockRepoDeleter(mockCtrl)
	mockCleanup := mocks.NewMockRepoCleanup(mockCtrl)
	cmd := newRepoDeleterCmd(mockService, mockCleanup, args)

	return ctx, mockService, mockCleanup, cmd
}

func TestArgs_ValidArgs(t *testing.T) {
	// capture logger output
	in := os.Stdout
	r, w, _ := os.Pipe()
	os.Stdout = w

	// set up args for test
	os.Args = []string{jobName, "--delete", "--limit=1", "--repositoryID=1", "--deadline=1"}

	// act
	_ = RepoDeleterMainCmd.Execute()

	w.Close()
	out, _ := io.ReadAll(r)
	os.Stdout = in

	// assert
	output := string(out)
	require.Contains(t, output, "repo-deleter completed")
	require.NotContains(t, output, "parse error")
}

func TestFindRepositoriesForDeletion_WithReposFound(t *testing.T) {
	// capture logger output
	in := os.Stdout
	r, w, _ := os.Pipe()
	os.Stdout = w
	ctx, service, cleanup, cmd := setup(t, w, arguments{delete: true})

	repo1, repo2 := ts.RepositoryEID(1), ts.RepositoryEID(2)
	repoIDs := []ts.RepositoryEID{repo1, repo2}
	repos := []*ts.DeletedRepository{{RepositoryID: repo1}, {RepositoryID: repo2}}

	service.EXPECT().
		FindRepositoriesForDeletion(ctx, cmd.args.repositoryID, cmd.args.limit).
		Return(repos, nil)

	service.EXPECT().DeletedRepositoriesOnDotcom(ctx, repoIDs).Return(repoIDs, nil)

	for _, repo := range repos {
		cleanup.EXPECT().DeadlineExceeded().Return(false).Times(1)
		cleanup.EXPECT().BlobData(ctx, repo.RepositoryID).Return(nil).Times(1)
		cleanup.EXPECT().MySQLData(ctx, repo.RepositoryID).Return(nil).Times(1)
		cleanup.EXPECT().ElasticSearchData(ctx, repo.RepositoryID).Return(nil).Times(1)
		service.EXPECT().CompleteDeleteProgress(ctx, repo.RepositoryID)
	}

	err := cmd.run(ctx)
	require.NoError(t, err)

	w.Close()
	out, _ := io.ReadAll(r)
	os.Stdout = in
	expectedLogMessage := "Found repositories to be deleted"
	require.Contains(t, string(out), expectedLogMessage)
}

func TestFindRepositoriesForDeletion_WithNoReposFound(t *testing.T) {
	// capture logger output
	in := os.Stdout
	r, w, _ := os.Pipe()
	os.Stdout = w
	ctx, service, _, cmd := setup(t, w, arguments{})

	service.EXPECT().
		FindRepositoriesForDeletion(ctx, cmd.args.repositoryID, cmd.args.limit).
		Return([]*ts.DeletedRepository{}, nil)

	service.EXPECT().DeletedRepositoriesOnDotcom(ctx, gomock.Any()).Times(0)

	err := cmd.run(ctx)
	require.NoError(t, err)

	w.Close()
	out, _ := io.ReadAll(r)
	os.Stdout = in
	expectedLogMessage := "No repositories to delete were found"
	require.Contains(t, string(out), expectedLogMessage)
}

func TestFindRepositoriesForDeletion_WithError(t *testing.T) {
	ctx, service, _, cmd := setup(t, os.Stdout, arguments{})

	expectedErr := errors.New("some failure from deleted-repos service")
	service.EXPECT().
		FindRepositoriesForDeletion(ctx, cmd.args.repositoryID, cmd.args.limit).
		Return([]*ts.DeletedRepository{}, expectedErr)

	service.EXPECT().DeletedRepositoriesOnDotcom(ctx, gomock.Any()).Times(0)

	err := cmd.run(ctx)
	require.ErrorIs(t, err, expectedErr)
}

func TestRepoID_FoundInDB(t *testing.T) {
	const argRepoID = 1
	ctx, service, cleanup, cmd := setup(t, os.Stdout, arguments{repositoryID: argRepoID, delete: true})

	repoIDs := []ts.RepositoryEID{argRepoID}
	repos := []*ts.DeletedRepository{{RepositoryID: argRepoID}}

	service.EXPECT().
		FindRepositoriesForDeletion(ctx, ts.RepositoryEID(argRepoID), cmd.args.limit).
		Return(repos, nil)

	service.EXPECT().DeletedRepositoriesOnDotcom(ctx, repoIDs).Return(repoIDs, nil).Times(1)

	// repoID = 1 that was passed as the CLI arg should be deleted
	cleanup.EXPECT().DeadlineExceeded().Return(false).Times(1)
	cleanup.EXPECT().BlobData(ctx, ts.RepositoryEID(argRepoID)).Return(nil).Times(1)
	cleanup.EXPECT().MySQLData(ctx, ts.RepositoryEID(argRepoID)).Return(nil).Times(1)
	cleanup.EXPECT().ElasticSearchData(ctx, ts.RepositoryEID(argRepoID)).Return(nil).Times(1)
	service.EXPECT().CompleteDeleteProgress(ctx, ts.RepositoryEID(argRepoID))

	err := cmd.run(ctx)
	require.NoError(t, err)
}

func TestRepoID_NotFoundInDB(t *testing.T) {
	const argRepoID = 1
	ctx, service, cleanup, cmd := setup(t, os.Stdout, arguments{repositoryID: argRepoID})

	service.EXPECT().
		FindRepositoriesForDeletion(ctx, ts.RepositoryEID(argRepoID), cmd.args.limit).
		Return([]*ts.DeletedRepository{}, nil)

	service.EXPECT().DeletedRepositoriesOnDotcom(ctx, gomock.Any()).Times(0)

	cleanup.EXPECT().BlobData(ctx, ts.RepositoryEID(argRepoID)).Return(nil).Times(0)
	cleanup.EXPECT().MySQLData(ctx, ts.RepositoryEID(argRepoID)).Return(nil).Times(0)
	cleanup.EXPECT().ElasticSearchData(ctx, ts.RepositoryEID(argRepoID)).Return(nil).Times(0)
	service.EXPECT().CompleteDeleteProgress(ctx, ts.RepositoryEID(argRepoID)).Times(0)

	err := cmd.run(ctx)
	require.NoError(t, err)
}

func TestDeleteFlag_False(t *testing.T) {
	// capture logger output
	in := os.Stdout
	r, w, _ := os.Pipe()
	os.Stdout = w
	ctx, service, cleanup, cmd := setup(t, w, arguments{delete: false})

	repo1, repo2 := ts.RepositoryEID(1), ts.RepositoryEID(2)
	repoIDs := []ts.RepositoryEID{repo1, repo2}
	repos := []*ts.DeletedRepository{{RepositoryID: repo1}, {RepositoryID: repo2}}

	service.EXPECT().
		FindRepositoriesForDeletion(ctx, cmd.args.repositoryID, cmd.args.limit).
		Return(repos, nil)

	cleanup.EXPECT().DeadlineExceeded().Return(false).Times(2)
	cleanup.EXPECT().BlobData(ctx, gomock.Any()).Return(nil).Times(0)
	cleanup.EXPECT().MySQLData(ctx, gomock.Any()).Return(nil).Times(0)
	cleanup.EXPECT().ElasticSearchData(ctx, gomock.Any()).Return(nil).Times(0)
	service.EXPECT().CompleteDeleteProgress(ctx, gomock.Any()).Times(0)

	service.EXPECT().DeletedRepositoriesOnDotcom(ctx, repoIDs).Return(repoIDs, nil).Times(1)

	err := cmd.run(ctx)
	require.NoError(t, err)

	w.Close()
	out, _ := io.ReadAll(r)
	os.Stdout = in
	expectedLogMessage := "Would have deleted but skipping due to dry-run"
	require.Contains(t, string(out), expectedLogMessage)
}

func TestDeadline(t *testing.T) {
	ctx, service, cleanup, cmd := setup(t, os.Stdout, arguments{})

	repo1, repo2 := ts.RepositoryEID(1), ts.RepositoryEID(2)
	repoIDs := []ts.RepositoryEID{repo1, repo2}
	repos := []*ts.DeletedRepository{{RepositoryID: repo1}, {RepositoryID: repo2}}

	service.EXPECT().
		FindRepositoriesForDeletion(ctx, cmd.args.repositoryID, cmd.args.limit).
		Return(repos, nil)

	service.EXPECT().DeletedRepositoriesOnDotcom(ctx, repoIDs).Return(repoIDs, nil).Times(1)

	cleanup.EXPECT().DeadlineExceeded().Return(true).Times(1)
	err := cmd.run(ctx)
	require.ErrorIs(t, err, executionStoppedErr)
}

func TestSkipped(t *testing.T) {
	ctx, service, cleanup, cmd := setup(t, os.Stdout, arguments{delete: true})

	repos := []*ts.DeletedRepository{{RepositoryID: 1}}
	repoIDs := []ts.RepositoryEID{repos[0].RepositoryID}

	service.EXPECT().
		FindRepositoriesForDeletion(ctx, cmd.args.repositoryID, cmd.args.limit).
		Return(repos, nil)

	service.EXPECT().DeletedRepositoriesOnDotcom(ctx, repoIDs).Return(repoIDs, nil).Times(1)
	cleanup.EXPECT().DeadlineExceeded().Return(false).Times(1)
	cleanup.EXPECT().BlobData(ctx, repos[0].RepositoryID).Return(repository.ErrCleanupStopped).Times(1)

	err := cmd.run(ctx)
	require.ErrorIs(t, err, executionStoppedErr)
}

func TestDeletedRepositoriesOnDotcom_UnconfirmedRepoNotDeleted(t *testing.T) {
	ctx, service, cleanup, cmd := setup(t, os.Stdout, arguments{delete: true})

	// set up two repos which will be returned from the ts_deleted_repositories table
	repo1, repo2 := ts.RepositoryEID(1), ts.RepositoryEID(2)
	repoIDs := []ts.RepositoryEID{repo1, repo2}
	repos := []*ts.DeletedRepository{{RepositoryID: repo1}, {RepositoryID: repo2}}

	service.EXPECT().
		FindRepositoriesForDeletion(ctx, cmd.args.repositoryID, cmd.args.limit).
		Return(repos, nil)

	// the call to the gh/gh API to confirm that these repos are still not found there, will only return the first repo as not_found.
	service.EXPECT().DeletedRepositoriesOnDotcom(ctx, repoIDs).Return(repoIDs[:1], nil)

	cleanup.EXPECT().DeadlineExceeded().Return(false).Times(2)

	// deletions should only be performed on repo1
	cleanup.EXPECT().BlobData(ctx, repo1).Return(nil).Times(1)
	cleanup.EXPECT().MySQLData(ctx, repo1).Return(nil).Times(1)
	cleanup.EXPECT().ElasticSearchData(ctx, repo1).Return(nil).Times(1)
	service.EXPECT().CompleteDeleteProgress(ctx, repo1).Return(nil).Times(1)

	// deletions should not be performed on repo2
	cleanup.EXPECT().BlobData(ctx, repo2).Return(nil).Times(0)
	cleanup.EXPECT().MySQLData(ctx, repo2).Return(nil).Times(0)
	cleanup.EXPECT().ElasticSearchData(ctx, repo2).Return(nil).Times(0)
	service.EXPECT().CompleteDeleteProgress(ctx, repo2).Return(nil).Times(0)

	err := cmd.run(ctx)
	require.NoError(t, err)
}

func TestDeletedRepositoriesOnDotcom_WithError(t *testing.T) {
	ctx, service, cleanup, cmd := setup(t, os.Stdout, arguments{})

	// set up two repos which will be returns from the ts_deleted_repositories table
	repo1, repo2 := ts.RepositoryEID(1), ts.RepositoryEID(2)
	repoIDs := []ts.RepositoryEID{repo1, repo2}
	repos := []*ts.DeletedRepository{{RepositoryID: repo1}, {RepositoryID: repo2}}

	service.EXPECT().
		FindRepositoriesForDeletion(ctx, cmd.args.repositoryID, cmd.args.limit).
		Return(repos, nil)

	expectedErr := errors.New("some failure from deleted-repos service")
	service.EXPECT().DeletedRepositoriesOnDotcom(ctx, repoIDs).Return([]ts.RepositoryEID{}, expectedErr)

	cleanup.EXPECT().DeadlineExceeded().Return(false).Times(0)
	cleanup.EXPECT().BlobData(ctx, gomock.Any()).Return(nil).Times(0)
	cleanup.EXPECT().ElasticSearchData(ctx, gomock.Any()).Return(nil).Times(0)

	err := cmd.run(ctx)
	require.ErrorIs(t, err, expectedErr)
}
