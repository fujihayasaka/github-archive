package suggested_fixes

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/jobs"
	"github.com/github/turboscan/ts/proto"
	"github.com/stretchr/testify/require"
)

func TestGenerateDependabotFix(t *testing.T) {
	_, ctx, twirpServ, _, aqMock, _, _ := setupService(t)

	req := &proto.GenerateDependabotFixRequest{
		RequestId:    100,
		RepositoryId: 200,
		CommitOid:    "1001",
		Sarif:        "some-sarif",
		FilePaths:    []string{"test.js"},
	}

	res, err := twirpServ.GenerateDependabotFix(ctx, req)
	require.NoError(t, err)
	require.True(t, res.Success)

	require.Len(t, aqMock.EnqueuedJobs(), 1)
	job := aqMock.EnqueuedJobs()[0]
	require.Equal(t, "GenerateDependabotFixJob", job.Name())

	actual, _ := job.(jobs.GenerateDependabotFixJob)
	require.Equal(t, req.RequestId, actual.RequestId)
	require.Equal(t, ts.RepositoryEID(req.RepositoryId), actual.RepoID)
	require.Equal(t, ts.Sha(req.CommitOid), actual.CommitOid)
	require.Equal(t, req.FilePaths, actual.FilePaths)
}
