package jobs

import (
	"context"
	"testing"

	tshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/flipper"
	"github.com/github/turboscan/ts/limits"
	asdb "github.com/github/turboscan/ts/mysql/alert"
	"github.com/github/turboscan/ts/mysql/archiver"
	sfdb "github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/sarif/store"
	sf "github.com/github/turboscan/ts/suggestedfixes"
	"github.com/github/turboscan/ts/twirp/clients/aqueduct"
	"github.com/github/turboscan/ts/twirp/clients/spokes"
	"github.com/stretchr/testify/require"
)

func Test_GenerateDependabotFixJob_perform_valid_fix(t *testing.T) {
	ctx := context.Background()
	ctx = flipper.WithFeatureEnabled(ctx, flipper.DependabotAutofix)

	db := dbtest.RequireConnection(t)
	s := sfdb.NewService(db)
	ls := limits.TestLimitSelector()
	as := asdb.TestService(db)
	arch := archiver.NewService(db, store.TestMemoryStore())
	mockSpokes := &spokes.MockSpokes{}

	sfServ := sf.New(s, as, arch, ls, mockSpokes, sf.NewMockValidFixGenerator())
	publisher := NewMockPublisher()
	sfServ.DependabotAutofixResultPublisher = publisher

	requestId := uint32(100)
	repoID := ts.RepositoryEID(1)
	filePaths := []string{
		"src/index.js",
	}
	commitOid := "123456"
	for _, fp := range filePaths {
		mockSpokes.AddFile(spokes.Filename(fp), spokes.CommitOID(commitOid), []byte("some content"))
	}
	sarif := "{}"
	job := &GenerateDependabotFixJob{
		RequestId: requestId,
		RepoID:    repoID,
		CommitOid: ts.Sha(commitOid),
		FilePaths: filePaths,
		Sarif:     sarif,
	}

	err := job.perform(ctx, sfServ)
	require.NoError(t, err)

	require.NotNil(t, publisher.event)
	require.Equal(t, requestId, publisher.event.RequestId)
	require.Equal(t, tshydro.DependabotAutofixResult_DEPENDABOT_AUTOFIX_RESULT_STATE_VALID, publisher.event.State)
	sf := publisher.event.SuggestedFix
	require.NotNil(t, sf)
	require.Equal(t, "some description", sf.Description)
	require.Len(t, sf.Files, 1)
	f := sf.Files[0]
	require.Equal(t, filePaths[0], f.FilePath)
	// assert formatted diff
	require.Equal(t, "diff --git a/src/index.js b/src/index.js\nindex 1234567..abcdefg 100644", string(f.DiffContent))
}

func Test_GenerateDependabotFixJob_perform_invalid_fix(t *testing.T) {
	ctx := context.Background()
	ctx = flipper.WithFeatureEnabled(ctx, flipper.DependabotAutofix)

	db := dbtest.RequireConnection(t)
	s := sfdb.NewService(db)
	ls := limits.TestLimitSelector()
	as := asdb.TestService(db)
	arch := archiver.NewService(db, store.TestMemoryStore())
	mockSpokes := &spokes.MockSpokes{}

	sfServ := sf.New(s, as, arch, ls, mockSpokes, sf.NewMockInvalidFixGenerator())
	publisher := NewMockPublisher()
	sfServ.DependabotAutofixResultPublisher = publisher

	requestId := uint32(100)
	repoID := ts.RepositoryEID(1)
	filePaths := []string{
		"src/index.js",
	}
	commitOid := "123456"
	for _, fp := range filePaths {
		mockSpokes.AddFile(spokes.Filename(fp), spokes.CommitOID(commitOid), []byte("some content"))
	}
	sarif := "{}"
	job := &GenerateDependabotFixJob{
		RequestId: requestId,
		RepoID:    repoID,
		CommitOid: ts.Sha(commitOid),
		FilePaths: filePaths,
		Sarif:     sarif,
	}

	err := job.perform(ctx, sfServ)
	require.NoError(t, err)

	require.NotNil(t, publisher.event)
	require.Equal(t, requestId, publisher.event.RequestId)
	require.Equal(t, tshydro.DependabotAutofixResult_DEPENDABOT_AUTOFIX_RESULT_STATE_INVALID, publisher.event.State)
	sf := publisher.event.SuggestedFix
	require.Nil(t, sf)
}

func Test_GenerateDependabotFixJob_RetriesOnTransientError(t *testing.T) {
	// Setup environment
	ctx := context.Background()
	ctx = flipper.WithFeatureEnabled(ctx, flipper.DependabotAutofix)

	db := dbtest.RequireConnection(t)

	sfDB := sfdb.NewService(db)
	asDB := asdb.TestService(db)
	arch := archiver.NewService(db, store.TestMemoryStore())
	ls := limits.TestLimitSelector()
	mockSpokes := &spokes.MockSpokes{}
	sfServ := sf.New(sfDB, asDB, arch, ls, mockSpokes, sf.NewMockTransientErrorFixGenerator())
	publisher := NewMockPublisher()
	sfServ.DependabotAutofixResultPublisher = publisher
	s := &aqueduct.TSServices{
		SuggestedFixes: sfServ,
		Aqueduct:       &aqueduct.AqueductMock{},
	}

	requestId := uint32(100)
	repoID := ts.RepositoryEID(1)
	filePaths := []string{
		"src/index.js",
	}
	commitOid := "123456"
	for _, fp := range filePaths {
		mockSpokes.AddFile(spokes.Filename(fp), spokes.CommitOID(commitOid), []byte("some content"))
	}
	sarif := "{}"
	job := &GenerateDependabotFixJob{
		RequestId: requestId,
		RepoID:    repoID,
		CommitOid: ts.Sha(commitOid),
		FilePaths: filePaths,
		Sarif:     sarif,
	}

	err := job.Perform(ctx, s)
	require.Error(t, err) // If the Perform returns an error, the aqueduct worker will retry the job

	// should not get any publish event
	require.Nil(t, publisher.event)

	// Test that the job marks the sfa as error if the last retry fails
	newCtx := appctx.WithAqueductJobRetryCount(ctx, aqueduct.MaxRetryCount)
	err = job.Perform(newCtx, s)
	require.Error(t, err) // The perform should still return the error
	require.NotNil(t, publisher.event)
	require.Equal(t, requestId, publisher.event.RequestId)
	require.Equal(t, tshydro.DependabotAutofixResult_DEPENDABOT_AUTOFIX_RESULT_STATE_ERROR, publisher.event.State)
	sf := publisher.event.SuggestedFix
	require.Nil(t, sf)
}

type MockDependabotAutofixResultPublisher struct {
	event *tshydro.DependabotAutofixResult
}

func (p *MockDependabotAutofixResultPublisher) PublishDependabotAutofixResult(_ context.Context, m *tshydro.DependabotAutofixResult) error {
	p.event = m

	return nil
}

func NewMockPublisher() *MockDependabotAutofixResultPublisher {
	return &MockDependabotAutofixResultPublisher{}
}
