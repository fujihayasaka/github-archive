package embeddings

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/require"

	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/github/githubfakes"
	"github.com/github/blackbird-mw/internal/publish/repo"
	"github.com/github/blackbird-mw/internal/test/mocks"
)

func Test_Deletes(t *testing.T) {
	cir1 := &github.CopilotIndexedRepository{
		RepositoryID:    1234,
		LastRequestedAt: time.Now().Add(-time.Hour * 24 * 30).UTC(),
	}
	cir2 := &github.CopilotIndexedRepository{
		RepositoryID:    3,
		LastRequestedAt: time.Now().UTC(),
	}
	fakeInternalAPI := &githubfakes.FakeInternalAPIClient{}
	fakeInternalAPI.GetCopilotIndexedRepositoriesReturns([]*github.CopilotIndexedRepository{cir1, cir2}, nil)
	fakeInternalAPI.DeleteCopilotIndexedRepositoryReturns(http.StatusNoContent, nil)

	fakeSyncProducer := &mocks.FakeSyncProducer{}

	maintenance := NewMaintenance(
		fakeInternalAPI,
		repo.NewPublisher(fakeSyncProducer, 1),
	)

	next := &github.CopilotIndexedRepository{}
	err := maintenance.run(context.Background(), next, time.Now().Add(-time.Hour*24*cutoffDays).UTC())
	require.NoError(t, err)
	require.EqualValues(t, next.RepositoryID, 0)
	require.EqualValues(t, next.LastRequestedAt, cir2.LastRequestedAt)
	require.Equal(t, 1, fakeInternalAPI.DeleteCopilotIndexedRepositoryCallCount())
	require.Equal(t, 0, fakeInternalAPI.UpdateCopilotIndexedRepositoryCallCount())
	require.Equal(t, 1, fakeSyncProducer.SendMessageCallCount())
}

func Test_Updates(t *testing.T) {
	cir1 := &github.CopilotIndexedRepository{
		RepositoryID:    1234,
		LastRequestedAt: time.Now().Add(-time.Hour * 24 * 30).UTC(),
	}
	cir2 := &github.CopilotIndexedRepository{
		RepositoryID:    3,
		LastRequestedAt: time.Now().UTC(),
	}
	fakeInternalAPI := &githubfakes.FakeInternalAPIClient{}
	fakeInternalAPI.GetCopilotIndexedRepositoriesReturns([]*github.CopilotIndexedRepository{cir1, cir2}, nil)
	fakeInternalAPI.DeleteCopilotIndexedRepositoryReturns(http.StatusMethodNotAllowed, nil)
	fakeInternalAPI.UpdateCopilotIndexedRepositoryReturns(http.StatusNoContent, nil)

	fakeSyncProducer := &mocks.FakeSyncProducer{}

	maintenance := NewMaintenance(
		fakeInternalAPI,
		repo.NewPublisher(fakeSyncProducer, 1),
	)

	next := cir1
	err := maintenance.run(context.Background(), next, time.Now().Add(-time.Hour*24*cutoffDays).UTC())
	require.NoError(t, err)
	require.EqualValues(t, 0, next.RepositoryID)
	require.EqualValues(t, cir2.LastRequestedAt, next.LastRequestedAt)
	require.Equal(t, 1, fakeInternalAPI.DeleteCopilotIndexedRepositoryCallCount())
	require.Equal(t, 1, fakeInternalAPI.UpdateCopilotIndexedRepositoryCallCount())
}

func Test_404Scenario(t *testing.T) {
	cir1 := &github.CopilotIndexedRepository{
		RepositoryID:    1234,
		LastRequestedAt: time.Now().Add(-time.Hour * 24 * 30).UTC(),
	}
	cir2 := &github.CopilotIndexedRepository{
		RepositoryID:    3,
		LastRequestedAt: time.Now().UTC(),
	}
	fakeInternalAPI := &githubfakes.FakeInternalAPIClient{}
	fakeInternalAPI.GetCopilotIndexedRepositoriesReturns([]*github.CopilotIndexedRepository{cir1, cir2}, nil)
	fakeInternalAPI.DeleteCopilotIndexedRepositoryReturns(http.StatusNotFound, nil)

	fakeSyncProducer := &mocks.FakeSyncProducer{}

	maintenance := NewMaintenance(
		fakeInternalAPI,
		repo.NewPublisher(fakeSyncProducer, 1),
	)

	next := cir1
	err := maintenance.run(context.Background(), next, time.Now().Add(-time.Hour*24*cutoffDays).UTC())
	require.NoError(t, err)
	require.EqualValues(t, 0, next.RepositoryID)
	require.EqualValues(t, cir2.LastRequestedAt, next.LastRequestedAt)
	require.Equal(t, 1, fakeInternalAPI.DeleteCopilotIndexedRepositoryCallCount())
	require.Equal(t, 0, fakeInternalAPI.UpdateCopilotIndexedRepositoryCallCount())
	require.Equal(t, 1, fakeSyncProducer.SendMessageCallCount())
}

func Test_LastRequestedAtAfterCutoff(t *testing.T) {
	// NB: Work stops when the first cir whose last requested at timestamp is after the cutoff.
	cir1 := &github.CopilotIndexedRepository{
		RepositoryID:    1234,
		LastRequestedAt: time.Now().UTC(),
	}
	cir2 := &github.CopilotIndexedRepository{
		RepositoryID:    3,
		LastRequestedAt: time.Now().UTC(),
	}
	fakeInternalAPI := &githubfakes.FakeInternalAPIClient{}
	fakeInternalAPI.GetCopilotIndexedRepositoriesReturns([]*github.CopilotIndexedRepository{cir1, cir2}, nil)

	fakeSyncProducer := &mocks.FakeSyncProducer{}

	maintenance := NewMaintenance(
		fakeInternalAPI,
		repo.NewPublisher(fakeSyncProducer, 1),
	)

	next := &github.CopilotIndexedRepository{}
	err := maintenance.run(context.Background(), next, time.Now().Add(-time.Hour*24*cutoffDays).UTC())
	require.NoError(t, err)
	cir1.RepositoryID = 0
	require.Equal(t, cir1, next)
	require.Equal(t, 0, fakeInternalAPI.DeleteCopilotIndexedRepositoryCallCount())
	require.Equal(t, 0, fakeInternalAPI.UpdateCopilotIndexedRepositoryCallCount())
	require.Equal(t, 0, fakeSyncProducer.SendMessageCallCount())
}
