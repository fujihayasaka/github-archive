package mysql

import (
	"context"
	"database/sql"
	"testing"

	throttler "github.com/github/go-freno-client"
	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/mysqlerrors"
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
	require.Equal(t, initialSeqNo.Int64+1, result.Repository.CommitSeqNo.Int64)
	require.Equal(t, refTip.CommitOID.Bytes(), result.Repository.CommitOID)
	require.Equal(t, ghRepo.Experiments, result.Repository.Experiments)
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
	require.True(t, result.Repository.CommitSeqNo.Valid)
	require.Equal(t, int64(1), result.Repository.CommitSeqNo.Int64)
	require.Equal(t, refTip.CommitOID.Bytes(), result.Repository.CommitOID)
}

func Test_RepositorySequenceTransactionalNewRepository(t *testing.T) {
	ctx := context.Background()
	conn := testDB(t)
	store := New(conn, throttler.DefaultThrottler)
	dbRepo := helpers.Repositories(t, 1)[0]
	ghRepo := helpers.GitHubRepositoryFromRepository(t, dbRepo)
	refTip1 := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)}
	refTip2 := &gitaccess.RefTip{RefName: "refs/heads/main", CommitOID: helpers.UniqueOID(t)}
	initialSeqNo := sql.NullInt64{Int64: 1, Valid: true}
	dbRepo.CommitSeqNo = initialSeqNo

	tx1Ready := make(chan bool)
	defer close(tx1Ready)
	tx1Done := make(chan bool)
	defer close(tx1Done)
	tx2Done := make(chan bool)
	defer close(tx2Done)

	var result *db.RepositoryResult
	var errA error
	go func() {
		result, errA = store.RepositorySequence(ctx, dbRepo.RepoID, func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
			tx1Ready <- true
			<-tx2Done
			return nil, ghRepo, refTip1, nil
		})
		tx1Done <- true
	}()

	<-tx1Ready
	_, err := store.RepositorySequence(ctx, dbRepo.RepoID, func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
		// This first callback response is used to determine the existing
		// repo's state in the db is different from the external state.
		// And then will attempt to open a txn.
		return nil, ghRepo, refTip2, nil
	})
	require.Error(t, err)
	require.ErrorIs(t, err, mysqlerrors.NoWaitLockError())
	require.Nil(t, result)

	tx2Done <- true
	<-tx1Done

	// the repo should have its sequence number incremented by 1 and commit details from refTip1
	require.NoError(t, errA)
	require.True(t, result.Repository.CommitSeqNo.Valid)
	require.Equal(t, initialSeqNo.Int64, result.Repository.CommitSeqNo.Int64)
	require.Equal(t, refTip1.CommitOID.Bytes(), result.Repository.CommitOID)
}

func Test_RepositorySequenceTransactionalExistingRepository(t *testing.T) {
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

	tx1FirstReady := make(chan bool)
	defer close(tx1FirstReady)
	tx1SecondReady := make(chan bool)
	defer close(tx1SecondReady)
	tx1Done := make(chan bool)
	defer close(tx1Done)
	tx2Ready := make(chan bool)
	defer close(tx2Ready)
	tx2Done := make(chan bool)
	defer close(tx2Done)

	var result *db.RepositoryResult
	var errA error
	// To ensure a transaction is opened, some state change must be detected between the existing
	// repo state in the db compared with the repo's external state. In this case, the owner ID is changed.
	changedGHRepo := ghRepo
	changedGHRepo.OwnerID = 999
	go func() {
		result, errA = store.RepositorySequence(ctx, dbRepo.RepoID, func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
			select {
			case <-tx1FirstReady: // signals when the 1st callback is invoked, before the txn is opened.
			case <-tx1SecondReady: // signals when the 2nd callback is invoked, after the txn is opened.
				<-tx2Ready // block until 2nd transaction attempt begins.
				<-tx2Done  // block until 2nd transaction attempt completes with NoWaitLockError.
			}
			return nil, changedGHRepo, refTip1, nil
		})
		tx1Done <- true
	}()

	tx1FirstReady <- true  // Signal the first callback to proceed.
	tx1SecondReady <- true // Signal the second callback to proceed.
	_, err := store.RepositorySequence(ctx, dbRepo.RepoID, func(ctx context.Context, state db.RepoInfoState) (*db.SkipReason, *github.Repository, *gitaccess.RefTip, error) {
		// This first callback response is used to determine the existing
		// repo's state in the db is different from the external state.
		// And then will attempt to open a txn.
		tx2Ready <- true
		return nil, changedGHRepo, refTip2, nil
	})
	require.Error(t, err)
	require.ErrorIs(t, err, mysqlerrors.NoWaitLockError())
	require.Nil(t, result)

	tx2Done <- true
	<-tx1Done

	// the repo should have its sequence number incremented by 1 and commit details from refTip1
	require.NoError(t, errA)
	require.True(t, result.Repository.CommitSeqNo.Valid)
	require.Equal(t, initialSeqNo.Int64+1, result.Repository.CommitSeqNo.Int64)
	require.Equal(t, refTip1.CommitOID.Bytes(), result.Repository.CommitOID)
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
