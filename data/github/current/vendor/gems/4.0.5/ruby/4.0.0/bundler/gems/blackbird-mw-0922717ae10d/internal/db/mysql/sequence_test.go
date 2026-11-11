package mysql

import (
	"context"
	"database/sql"
	"testing"

	throttler "github.com/github/go-freno-client/v2"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/repofilter"
	"github.com/github/blackbird-mw/internal/experiments"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/test/helpers"
	"github.com/github/blackbird-mw/internal/types"
)

func Test_RepositorySequenceForExistingRepo(t *testing.T) {
	ctx := context.Background()
	conn := testDB(t)
	store := New(conn, throttler.DefaultThrottler)
	dbRepo := helpers.Repositories(t, 1)[0]
	ghRepo := helpers.GitHubRepositoryFromRepository(t, dbRepo)
	ghRepo.Experiments = experiments.Experiments{experiments.EnableCodeEmbedding: "1"} // Verify that experiments are updated based on current GitHub repo state.
	refTip := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)}
	initialSeqNo := sql.NullInt64{Int64: 1, Valid: true}
	dbRepo.CommitSeqNo = initialSeqNo

	// Insert the repository so it already exists when RepositorySequence is called
	helpers.InsertRepositories(t, conn, dbRepo)
	repo, err := store.GetRepositoryByID(ctx, dbRepo.RepoID)
	require.NoError(t, err)
	require.True(t, repo.CommitSeqNo.Valid)
	require.Equal(t, int64(1), repo.CommitSeqNo.Int64)

	repoInfo := func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
		return nil, ghRepo, refTip, nil
	}

	result, err := store.RepositorySequence(ctx, dbRepo.RepoID, repoInfo)
	require.NoError(t, err)
	require.True(t, result.Repository.CommitSeqNo.Valid)
	require.Equal(t, int64(2), result.Repository.CommitSeqNo.Int64)
	require.Equal(t, refTip.CommitOID.Bytes(), result.Repository.CommitOID)
	require.Equal(t, ghRepo.Experiments, result.Repository.Experiments)

	repo, err = store.GetRepositoryByID(ctx, dbRepo.RepoID)
	require.NoError(t, err)
	require.True(t, repo.CommitSeqNo.Valid)
	require.Equal(t, int64(2), repo.CommitSeqNo.Int64)
}

// This will be the case for all repositories when we roll this out: the SQL update must properly handle NULLs
func Test_RepositorySequenceForExistingRepoWithNoSeqNo(t *testing.T) {
	ctx := context.Background()
	conn := testDB(t)
	store := New(conn, throttler.DefaultThrottler)
	dbRepo := helpers.Repositories(t, 1)[0]
	dbRepo.CommitSeqNo = sql.NullInt64{}
	ghRepo := helpers.GitHubRepositoryFromRepository(t, dbRepo)
	refTip := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)}

	// Insert the repository so it already exists when RepositorySequence is called
	helpers.InsertRepositories(t, conn, dbRepo)
	repo, err := store.GetRepositoryByID(ctx, dbRepo.RepoID)
	require.NoError(t, err)
	require.False(t, repo.CommitSeqNo.Valid)

	repoInfo := func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
		return nil, ghRepo, refTip, nil
	}

	result, err := store.RepositorySequence(ctx, dbRepo.RepoID, repoInfo)
	require.NoError(t, err)
	require.NotNil(t, result.Repository)
	require.True(t, result.Repository.CommitSeqNo.Valid)
	require.Equal(t, int64(1), result.Repository.CommitSeqNo.Int64)
	require.Equal(t, refTip.CommitOID.Bytes(), result.Repository.CommitOID)

	repo, err = store.GetRepositoryByID(ctx, dbRepo.RepoID)
	require.NoError(t, err)
	require.True(t, repo.CommitSeqNo.Valid)
	require.Equal(t, int64(1), repo.CommitSeqNo.Int64)
}

func Test_RepositorySequenceMultiProcessNewRepository(t *testing.T) {
	ctx := context.Background()
	conn := testDB(t)
	store := New(conn, throttler.DefaultThrottler)
	dbRepo := helpers.Repositories(t, 1)[0]
	ghRepo := helpers.GitHubRepositoryFromRepository(t, dbRepo)
	refTip1 := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)}
	refTip2 := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)}
	initialSeqNo := sql.NullInt64{Int64: 1, Valid: true}
	dbRepo.CommitSeqNo = initialSeqNo

	proc1Ready := make(chan bool)
	defer close(proc1Ready)
	proc1Done := make(chan bool)
	defer close(proc1Done)
	proc2Done := make(chan bool)
	defer close(proc2Done)

	var proc1Result *db.RepositoryResult
	var proc1Err error
	go func() {
		proc1Result, proc1Err = store.RepositorySequence(ctx, dbRepo.RepoID, func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
			proc1Ready <- true
			<-proc2Done
			return nil, ghRepo, refTip1, nil
		})
		proc1Done <- true
	}()

	<-proc1Ready
	proc2Result, proc2Err := store.RepositorySequence(ctx, dbRepo.RepoID, func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
		return nil, ghRepo, refTip2, nil
	})
	proc2Done <- true
	require.NoError(t, proc2Err)
	require.NotNil(t, proc2Result)

	<-proc1Done
	require.Error(t, proc1Err)
	require.ErrorIs(t, proc1Err, db.ErrInsertRaced)
	require.Nil(t, proc1Result)

	require.Equal(t, int64(1), proc2Result.Repository.CommitSeqNo.Int64)
	require.Equal(t, refTip2.CommitOID.Bytes(), proc2Result.Repository.CommitOID)

	repo, err := store.GetRepositoryByID(ctx, dbRepo.RepoID)
	require.NoError(t, err)
	require.True(t, repo.CommitSeqNo.Valid)
	require.Equal(t, int64(1), repo.CommitSeqNo.Int64)
}

func Test_RepositorySequenceMultiProcessExistingRepository(t *testing.T) {
	ctx := context.Background()
	conn := testDB(t)
	store := New(conn, throttler.DefaultThrottler)
	dbRepo := helpers.Repositories(t, 1)[0]
	ghRepo := helpers.GitHubRepositoryFromRepository(t, dbRepo)
	refTip1 := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)}
	refTip2 := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)}
	initialSeqNo := sql.NullInt64{Int64: 1, Valid: true}
	dbRepo.CommitSeqNo = initialSeqNo

	// Insert the repository so it already exists when RepositorySequence is called
	helpers.InsertRepositories(t, conn, dbRepo)

	proc1Ready := make(chan bool)
	defer close(proc1Ready)
	proc1Done := make(chan bool)
	defer close(proc1Done)
	proc2Done := make(chan bool)
	defer close(proc2Done)

	var proc1Result *db.RepositoryResult
	var proc1Err error
	changedGHRepo := ghRepo
	changedGHRepo.OwnerID = 999
	go func() {
		proc1Result, proc1Err = store.RepositorySequence(ctx, dbRepo.RepoID, func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
			// Process 2 will race with process 1, and will update the repository such that by the time process 1 attempts
			// to update the repository record, the commit sequence number will have changed. This should result in db.ErrUpdateRaced.
			proc1Ready <- true
			<-proc2Done
			return nil, changedGHRepo, refTip1, nil
		})
		proc1Done <- true
	}()

	<-proc1Ready
	proc2Result, proc2Err := store.RepositorySequence(ctx, dbRepo.RepoID, func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
		return nil, changedGHRepo, refTip2, nil
	})
	proc2Done <- true
	require.NoError(t, proc2Err)
	require.NotNil(t, proc2Result)

	<-proc1Done
	require.Nil(t, proc1Result)
	require.Error(t, proc1Err)
	require.ErrorIs(t, proc1Err, db.ErrUpdateRaced)

	require.True(t, proc2Result.Repository.CommitSeqNo.Valid)
	require.Equal(t, initialSeqNo.Int64+1, proc2Result.Repository.CommitSeqNo.Int64)
	require.Equal(t, refTip2.CommitOID.Bytes(), proc2Result.Repository.CommitOID)
}

func Test_RepositorySequenceNonExistingRepo(t *testing.T) {
	ctx := context.Background()
	conn := testDB(t)
	store := New(conn, throttler.DefaultThrottler)
	dbRepo := helpers.Repositories(t, 1)[0]
	ghRepo := helpers.GitHubRepositoryFromRepository(t, dbRepo)
	ghRepo.Experiments = experiments.Experiments{experiments.EnableCodeEmbedding: "1"} // Verify that experiments are inserted based on current GitHub repo state.
	refTip := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)}

	// The repository is not present
	repo, err := store.GetRepositoryByID(ctx, dbRepo.RepoID)
	require.NoError(t, err)
	require.Nil(t, repo)

	repoInfo := func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
		return nil, ghRepo, refTip, nil
	}

	result, err := store.RepositorySequence(ctx, dbRepo.RepoID, repoInfo)
	require.NoError(t, err)
	require.True(t, result.Repository.CommitSeqNo.Valid)
	require.Equal(t, int64(1), result.Repository.CommitSeqNo.Int64)
	require.Equal(t, refTip.CommitOID.Bytes(), result.Repository.CommitOID)
	require.Equal(t, ghRepo.Experiments, result.Repository.Experiments)

	repo, err = store.GetRepositoryByID(ctx, dbRepo.RepoID)
	require.NoError(t, err)
	require.True(t, repo.CommitSeqNo.Valid)
	require.Equal(t, int64(1), repo.CommitSeqNo.Int64)
}

func Test_ErroredRepositorySequenceExistingRepoDeletedArgFalse(t *testing.T) {
	ctx := context.Background()
	conn := testDB(t)
	store := New(conn, throttler.DefaultThrottler)
	repo := helpers.Repositories(t, 1)[0]
	repo.OwnerLogin = "owner"
	repo.Name = "exists"
	helpers.InsertRepositories(t, conn, repo)

	seqNos, err := store.ErroredRepositorySequence(ctx, repo.RepoID, false)
	require.NoError(t, err)
	require.Equal(t, uint64(2), seqNos.CommitSeqNo)
	require.Equal(t, types.RepoSeqNo(1), seqNos.RepoSeqNo)

	repo, err = store.GetFirstRepository(ctx, repofilter.ID(repo.RepoID))
	require.NoError(t, err)
	require.Equal(t, sql.NullInt64{Int64: 2, Valid: true}, repo.CommitSeqNo)
	require.Equal(t, sql.NullInt64{Int64: 1, Valid: true}, repo.RepoSeqNo)
	require.False(t, repo.DeletedAt.Valid)
	require.Equal(t, "owner", repo.OwnerLogin)
	require.Equal(t, "exists", repo.Name)
}

func Test_ErroredRepositorySequenceExistingRepoDeletedArgTrue(t *testing.T) {
	ctx := context.Background()
	conn := testDB(t)
	store := New(conn, throttler.DefaultThrottler)
	repo := helpers.Repositories(t, 1)[0]
	repo.OwnerLogin = "owner"
	repo.Name = "exists"
	helpers.InsertRepositories(t, conn, repo)

	seqNos, err := store.ErroredRepositorySequence(ctx, repo.RepoID, true /* delete the repo */)
	require.NoError(t, err)
	require.Equal(t, uint64(2), seqNos.CommitSeqNo)
	require.Equal(t, types.RepoSeqNo(1), seqNos.RepoSeqNo)

	repo, err = store.GetFirstRepository(ctx, repofilter.ID(repo.RepoID))
	require.NoError(t, err)
	require.Equal(t, sql.NullInt64{Int64: 2, Valid: true}, repo.CommitSeqNo)
	require.Equal(t, sql.NullInt64{Int64: 1, Valid: true}, repo.RepoSeqNo)
	require.True(t, repo.DeletedAt.Valid)
	require.Equal(t, "owner", repo.OwnerLogin)
	require.Equal(t, "exists", repo.Name)
}

func Test_RepositorySequenceDeleteRepo(t *testing.T) {
	ctx := context.Background()
	conn := testDB(t)
	store := New(conn, throttler.DefaultThrottler)
	repoID := helpers.RepoID(t)

	// The repository is not present
	repo, err := store.GetRepositoryByID(ctx, repoID)
	require.NoError(t, err)
	require.Nil(t, repo)

	seqNos, err := store.ErroredRepositorySequence(ctx, repoID, true /* delete the repo */)
	require.NoError(t, err)
	require.Equal(t, uint64(1), seqNos.CommitSeqNo)
	require.Equal(t, types.RepoSeqNo(0), seqNos.RepoSeqNo)

	repo, err = store.GetFirstRepository(ctx, repofilter.ID(repoID))
	require.NoError(t, err)
	require.Equal(t, sql.NullInt64{Int64: 1, Valid: true}, repo.CommitSeqNo)
	require.Equal(t, sql.NullInt64{Int64: 0, Valid: false}, repo.RepoSeqNo)
	require.True(t, repo.DeletedAt.Valid)
	require.Contains(t, repo.Name, "dummy")
	require.Contains(t, repo.OwnerLogin, "dummy")
}

// If we have to create a dummy repo, we ALWAYS mark it deleted.
func Test_RepositorySequenceNonExistentWhereDeleteArgIsFalse(t *testing.T) {
	ctx := context.Background()
	conn := testDB(t)
	store := New(conn, throttler.DefaultThrottler)
	repoID := helpers.RepoID(t)

	// The repository is not present
	repo, err := store.GetRepositoryByID(ctx, repoID)
	require.NoError(t, err)
	require.Nil(t, repo)

	seqNos, err := store.ErroredRepositorySequence(ctx, repoID, false /* don't mark it deleted */)
	require.NoError(t, err)
	require.Equal(t, uint64(1), seqNos.CommitSeqNo)
	require.Equal(t, types.RepoSeqNo(0), seqNos.RepoSeqNo)

	repo, err = store.GetFirstRepository(ctx, repofilter.ID(repoID))
	require.NoError(t, err)
	require.Equal(t, sql.NullInt64{Int64: 1, Valid: true}, repo.CommitSeqNo)
	require.Equal(t, sql.NullInt64{Int64: 0, Valid: false}, repo.RepoSeqNo)
	require.True(t, repo.DeletedAt.Valid, "expected dummy repository to be created with deleted_at set")
	require.Contains(t, repo.Name, "dummy")
	require.Contains(t, repo.OwnerLogin, "dummy")
}
