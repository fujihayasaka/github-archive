package consumers

import (
	"context"
	"testing"
	"time"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/mocks"
	gomock "go.uber.org/mock/gomock"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/go-stats"
	envelope "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	cshydro "github.com/github/hydro-schemas-go/hydro/schemas/code_scanning/v0"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/github/turboscan/ts/hydro/topics"
	"github.com/github/turboscan/ts/mysql/managedanalysis"
	"github.com/github/turboscan/ts/mysql/repository"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func createExpectedCodeqlRun(t *testing.T, eventType string) *cshydro.ManagedAnalysesExpectedCodeqlRun {
	t.Helper()
	return &cshydro.ManagedAnalysesExpectedCodeqlRun{
		RepositoryId:        1,
		OwnerId:             123,
		TriggeringEventType: eventType,
		TriggeringEventTime: timestamppb.New(time.Now().Add(-1 * time.Minute)),
		Ref:                 []byte("refs/heads/main"),
		CommitOid:           "123456",
		DefaultBranch:       true,
	}
}

func TestExpectedCodeqlRunProcess(t *testing.T) {
	msg := createExpectedCodeqlRun(t, "pull_request_create")
	db := dbtest.RequireConnectionWithoutAutoIncrement(t)
	mockCtrl := gomock.NewController(t)
	publisher := mocks.NewMockCodeqlRunPublisher(mockCtrl)
	ma := managedanalysis.NewService(db, publisher)
	run := &ts.CodeqlRun{
		RepositoryID:  1,
		WorkflowRunID: 123,
		ExecutionID:   "132",
		Status:        ts.CodeqlRunStatus_INPROGRESS,
		Sha:           "123456",
		Ref:           ts.Ref("refs/heads/main"),
	}
	dbtest.RequireCreate(t, db, run)
	reposervice := repository.NewService(db)
	createdAt := sqltime.Now()
	repo := &ts.Repository{
		RepositoryID:        1,
		OwnerID:             1,
		CodeScanningEnabled: true,
		SourceUpdatedAt:     createdAt,
		DefaultRef:          msg.Ref,
		BaseModel: ts.BaseModel{
			CreatedAt: createdAt,
		},
	}
	dbtest.RequireCreate(t, db, repo)
	testStatter := newTestStatter()
	ctx := appctx.WithStats(context.Background(), testStatter)
	processor := NewExpectedCodeqlRunProcessor(ma, reposervice)
	e, err := createEnvelope(t, msg)
	require.NoError(t, err)
	err = processor.ProcessEnvelope(
		ctx,
		e,
		topics.ManagedAnalysesExpectedCodeqlRun,
	)
	require.NoError(t, err)
	s, ok := testStatter.statistics["code_scanning.managed_analyses.run_triggered.slo"]
	require.True(t, ok)
	require.Equal(t, statistics{
		tags: stats.Tags{
			"default_branch": "true",
			"success":        "true",
			"trigger":        "pr",
		},
		value: 1,
	}, s)
}

type statistics struct {
	tags  stats.Tags
	value int64
}

type testStatter struct {
	stats.Client
	statistics map[string]statistics
}

func newTestStatter() *testStatter {
	c := stats.NullStatter
	return &testStatter{
		Client:     c,
		statistics: make(map[string]statistics),
	}
}

func (s *testStatter) Counter(key string, tags stats.Tags, value int64) {
	s.statistics[key] = statistics{
		tags:  tags,
		value: value,
	}
}

func createEnvelope(t *testing.T, msg proto.Message) (*envelope.Envelope, error) {
	t.Helper()
	data, err := proto.Marshal(msg)
	if err != nil {
		return nil, err
	}
	env := WrapEnvelope(t, data)

	var e envelope.Envelope
	err = UnwrapEnvelope(env, &e)
	if err != nil {
		return nil, err
	}
	return &e, err
}
