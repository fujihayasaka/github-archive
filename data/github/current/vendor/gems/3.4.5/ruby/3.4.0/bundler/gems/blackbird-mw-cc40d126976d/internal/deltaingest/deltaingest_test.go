package deltaingest

import (
	"context"
	"fmt"
	"strconv"
	"sync"
	"testing"
	"time"

	cachepb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/cache/v1"
	indexpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/index/v1"
	servingpb "github.com/github/blackbird/crates/client/pkg/blackbird/gen/serving/v1"
	hydropb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	blackbird_entities "github.com/github/hydro-schemas-go/hydro/schemas/blackbird/v0/entities"
	hydro_schemas_github_search_v0 "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	searchpb "github.com/github/hydro-schemas-go/hydro/schemas/github/search/v0"
	entitiespb "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/types/known/wrapperspb"

	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/noop"
	"github.com/github/blackbird-mw/internal/env"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/test/helpers"
)

func Test_IngestWorkersAndConsumeLoop(t *testing.T) {
	ctx := context.Background()
	config := env.New(ctx) // Load the config so logging is configured in case you run with `go test -v`
	defer config.Close()

	corpus := helpers.Corpus(t)
	repo := helpers.Repositories(t, 1)[0]
	store := noop.New(repo)
	_, err := store.SetCorpusIngestMode(ctx, corpus, db.IngestModeLegacy, db.IngestModeBackfill)
	require.NoError(t, err)
	state, err := store.GetCorpusState(ctx, corpus)
	require.NoError(t, err)

	messages := make(chan hydro.Message, 1)
	messages <- hydroMsg(t,
		&searchpb.RepositoryChanged{
			Repository: &entitiespb.Repository{
				Id:      uint32(repo.RepoID),
				OwnerId: &wrapperspb.UInt32Value{Value: repo.OwnerID},
				Name:    repo.Name,
			},
			OwnerName: repo.OwnerLogin,
		}, "test.topic", 1, 1)
	close(messages)
	backfillSource, err := hydro.NewMemorySource(messages)
	require.NoError(t, err)

	incrMessages := make(chan hydro.Message)
	close(incrMessages)
	incrSource, err := hydro.NewMemorySource(incrMessages)
	require.NoError(t, err)

	indexerCluster := helpers.IndexerCluster(t)
	indexerHost, err := indexerCluster.GetHost()
	require.NoError(t, err)
	fakeIndexAPI := helpers.FakeIndexAPI(t, indexerHost)
	cacheClusters := helpers.CacheClusters(t)
	client, err := cacheClusters.ClientForCluster(indexerCluster.CacheCluster())
	require.NoError(t, err)
	fakeCache := helpers.FakeCacheAPI(t, client, 0)

	fakeCache.PublishCacheDocumentStub = func(ctx context.Context, req *cachepb.PublishCacheDocumentRequest) (*cachepb.PublishCacheDocumentResponse, error) {
		// This is an empty cache, so alway return a miss
		return &cachepb.PublishCacheDocumentResponse{}, nil
	}
	fakeCache.PublishDeleteDocumentStub = func(ctx context.Context, req *cachepb.PublishDeleteDocumentRequest) (*cachepb.PublishDeleteDocumentResponse, error) {
		return &cachepb.PublishDeleteDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishDeleteDocumentCallCount() + fakeCache.PublishDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}
	fakeCache.PublishDocumentStub = func(ctx context.Context, req *cachepb.PublishDocumentRequest) (*cachepb.PublishDocumentResponse, error) {
		return &cachepb.PublishDocumentResponse{
			Published: &cachepb.Published{
				Partition:  0,
				Offset:     int64(fakeCache.PublishDeleteDocumentCallCount() + fakeCache.PublishDocumentCallCount()),
				AppendTime: time.Now().UnixMilli(),
			},
		}, nil
	}
	fakeIndexAPI.GetPermanentErrorReturns(&indexpb.GetPermanentErrorResponse{
		ServingStatus:      &servingpb.ServingStatus{},
		PermanentError:     "having an error prevents having to stub additional RPCs",
		PermanentErrorType: blackbird_entities.PermanentErrorType_RETRIES_EXHAUSTED,
		EntryId:            123,
	}, nil)
	fakeIndexAPI.SkipReturns(&indexpb.SkipResponse{
		ServingStatus: &servingpb.ServingStatus{},
		Barrier:       &blackbird_entities.TopicBarrier{},
	}, nil)

	consumer := NewIngestModeConsumer(
		ctx,
		store,
		corpus,
		backfillSource,
		incrSource,
		indexerCluster,
		state.EpochID,
	)
	err = RunWorkPool(
		ctx,
		1, /*num workers*/
		corpus,
		routing.TopicConfig{},
		store,
		consumer,
		nil, /*githubClient*/
		mockGitClient(t, helpers.RandomOID(t)),
		cacheClusters,
		indexerCluster,
		routing.Dotcom,
	)

	require.EqualError(t, err, "EOF")
}

//
// Test helpers and test operations
//

// The result of running a task.
type TaskResult struct {
	err  error
	task *Task
}

// BufferOp collects all input and done tasks for further inspection.
type BufferOp struct {
	inner     Op
	inTasks   []*Task
	doneTasks []*TaskResult
	mutex     sync.Mutex
}

func NewBufferOp(inner Op) *BufferOp {
	return &BufferOp{inner, []*Task{}, []*TaskResult{}, sync.Mutex{}}
}

func (o *BufferOp) Run(task *Task) {
	task.Begin(o)

	o.mutex.Lock()
	o.inTasks = append(o.inTasks, task)
	o.mutex.Unlock()

	o.inner.Run(task)
}

func (o *BufferOp) OnDone(task *Task, err error) {
	o.mutex.Lock()
	o.doneTasks = append(o.doneTasks, &TaskResult{err, task})
	o.mutex.Unlock()

	task.Done(err)
}

// An operation that immediately finishes tasks successfully and keeps a log of them.
type TestLogOp struct {
	mutex sync.Mutex
	log   []*Task
}

func NewTestLogOp() *TestLogOp {
	return &TestLogOp{}
}

func (o *TestLogOp) Run(task *Task) {
	task.Begin(o)
	func() {
		o.mutex.Lock()
		defer o.mutex.Unlock()
		o.log = append(o.log, task)
		fmt.Printf("echo running task %d\n", task.repoID())
	}()
	task.Done(nil)
}

func (o *TestLogOp) OnDone(task *Task, err error) {}

// Run should block simulating work being done and unblock when the test code
// wants to move it forward.
// The problem is when tasks queue other tasks - in that case we don't want Run to block...

// A special testing operation to simulate an ingest where the test code can
// control the finishing of the first task. Subsequent tasks run without
// blocking.
type TestIngestOp struct {
	mutex     sync.Mutex
	firstTask *Task
	wg        sync.WaitGroup
	tasks     []*Task
}

func NewTestIngestOp() *TestIngestOp {
	return &TestIngestOp{}
}

func (o *TestIngestOp) Run(task *Task) {
	task.Begin(o)

	shouldBlock := func() bool {
		o.mutex.Lock()
		defer o.mutex.Unlock()
		return o.firstTask == nil
	}()

	if shouldBlock {
		fmt.Printf("test ingest op: run: started first task %d\n", task.repoID())
		o.wg.Add(1)
		o.mutex.Lock()
		o.firstTask = task
		o.mutex.Unlock()
		o.wg.Wait()
	} else {
		fmt.Printf("test ingest op: run: started subsequent task %d\n", task.repoID())
		o.mutex.Lock()
		o.tasks = append(o.tasks, task)
		o.mutex.Unlock()
	}
	task.Done(nil)
	fmt.Printf("test ingest op: run: done with task %d\n", task.repoID())
}

func (o *TestIngestOp) OnDone(task *Task, err error) {}

func (o *TestIngestOp) FinishFirst() {
	avail := func() bool {
		o.mutex.Lock()
		defer o.mutex.Unlock()
		return o.firstTask != nil
	}

	for {
		time.Sleep(1 * time.Millisecond)
		if avail() {
			break
		}
	}

	fmt.Printf("test ingest op: finishing task %d\n", o.firstTask.repoID())
	o.wg.Done()
}

func (o *TestIngestOp) WaitUntilN(n int) {
	avail := func() bool {
		o.mutex.Lock()
		defer o.mutex.Unlock()
		return len(o.tasks) >= n
	}

	for {
		time.Sleep(1 * time.Millisecond)
		if avail() {
			break
		}
	}
}

// An operation that collects all tasks in a buffer. You can finish or fail
// individual tasks by calling FinishOne and/or FinishAll.
type TestCollectOp struct {
	tasks              []*Task
	mutex              sync.Mutex
	finishedTasks      []*TaskResult
	finishedTasksMutex sync.Mutex
}

func NewTestCollectOp() *TestCollectOp {
	return &TestCollectOp{[]*Task{}, sync.Mutex{}, []*TaskResult{}, sync.Mutex{}}
}

func (o *TestCollectOp) Run(task *Task) {
	task.Begin(o)

	o.mutex.Lock()
	defer o.mutex.Unlock()
	o.tasks = append(o.tasks, task)
}

func (o *TestCollectOp) OnDone(task *Task, err error) {}

func (o *TestCollectOp) WaitUntilN(n int) {
	avail := func() bool {
		o.mutex.Lock()
		defer o.mutex.Unlock()
		return len(o.tasks) >= n
	}

	for {
		time.Sleep(1 * time.Millisecond)
		if avail() {
			break
		}
	}
}

func (o *TestCollectOp) FinishCollected() {
	o.mutex.Lock()
	defer o.mutex.Unlock()

	for _, task := range o.tasks {
		o.finishTask(task, nil)
	}
	o.tasks = []*Task{}
}

func (o *TestCollectOp) WaitOne() {
	avail := func() bool {
		o.mutex.Lock()
		defer o.mutex.Unlock()
		return len(o.tasks) > 0
	}

	for {
		time.Sleep(1 * time.Millisecond)
		if avail() {
			break
		}
	}
}

// FinishFirstOne will block waiting for a task and finish it. If there are
// multiple tasks, it'll finish the first one that was run.
func (o *TestCollectOp) FinishFirstOne(err error) {
	pop := func() *Task {
		o.mutex.Lock()
		defer o.mutex.Unlock()

		if len(o.tasks) == 0 {
			return nil
		}

		t := o.tasks[0]
		o.tasks = o.tasks[1:]
		return t
	}

	for {
		time.Sleep(1 * time.Millisecond)
		if t := pop(); t != nil {
			o.finishTask(t, err)
			break
		}
	}
}

// FinishLastOne will block waiting for a task and finish it. If there are
// multiple tasks, it'll finish the last one that was run. NOTE that this
// finishes tasks out of order from which they were added.
func (o *TestCollectOp) FinishLastOne(err error) {
	pop := func() *Task {
		o.mutex.Lock()
		defer o.mutex.Unlock()

		if len(o.tasks) == 0 {
			return nil
		}

		t := o.tasks[len(o.tasks)-1]
		o.tasks = o.tasks[:len(o.tasks)-1]
		return t
	}

	for {
		time.Sleep(1 * time.Millisecond)
		if t := pop(); t != nil {
			o.finishTask(t, err)
			break
		}
	}
}

func (o *TestCollectOp) finishTask(task *Task, err error) {
	func() {
		o.finishedTasksMutex.Lock()
		defer o.finishedTasksMutex.Unlock()
		o.finishedTasks = append(o.finishedTasks, &TaskResult{err, task})
	}()

	task.Done(err)
}

func newTaskWithRepoID(t *testing.T, repo uint32) *Task {
	return newTaskWithRepo(t, repo, nil, hydro_schemas_github_search_v0.RepositoryChanged_ADMIN_PUSHED, routing.IncrementalSourceTopic, 1, 1)
}

func newTaskWithTopicPartitionOffset(t *testing.T, topic string, partition int32, offset int64) *Task {
	return newTaskWithRepo(t, 1, nil, hydro_schemas_github_search_v0.RepositoryChanged_ADMIN_PUSHED, topic, partition, offset)
}

func newTaskWithRepo(t *testing.T, repo uint32, ancestors []uint32, change hydro_schemas_github_search_v0.RepositoryChanged_Change, topic string, partition int32, offset int64) *Task {
	event := &hydro_schemas_github_search_v0.RepositoryChanged{
		Repository:               &entitiespb.Repository{Id: repo, OwnerId: &wrapperspb.UInt32Value{Value: 1}, Name: "test"},
		Change:                   change,
		OwnerName:                "test",
		BlackbirdAncestorRepoIds: ancestors,
	}
	return &Task{
		ctx:        context.Background(),
		msg:        hydroMsg(t, event, topic, partition, offset),
		event:      event,
		envelope:   &hydropb.Envelope{},
		receivedAt: time.Now(),
	}
}

func hydroMsg(t *testing.T, event *hydro_schemas_github_search_v0.RepositoryChanged, topic string, partition int32, offset int64) hydro.Message {
	encoder := hydro.NewDefaultEncoder()
	data, err := encoder.Encode(event, time.Now())
	require.NoError(t, err)

	key := strconv.Itoa(int(event.GetRepository().GetId()))

	return hydro.Message{
		Topic:     topic,
		Partition: partition,
		Offset:    offset,
		Key:       []byte(key),
		Value:     data,
	}
}
