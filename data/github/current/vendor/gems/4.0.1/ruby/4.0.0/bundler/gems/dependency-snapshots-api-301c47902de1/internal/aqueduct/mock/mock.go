package mock

import (
	"context"
	"time"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	aqueduct_api_v1 "github.com/github/aqueduct-client-go/v2/proto"
	aqueduct_maintenance_api_v1 "github.com/github/aqueduct-client-go/v2/proto/maintenance"
	"github.com/stretchr/testify/mock"
	"google.golang.org/protobuf/proto"
)

// MockedEnqueuer is a mock implementation of the Enqueuer interface.
type MockedEnqueuer struct {
	mock.Mock
}

func (m *MockedEnqueuer) Enqueue(ctx context.Context, j proto.Message) (string, error) {
	args := m.Called(ctx, j)
	return args.String(0), args.Error(1)
}

func (m *MockedEnqueuer) EnqueueWithRoute(ctx context.Context, j proto.Message, queue string) (string, error) {
	args := m.Called(ctx, j, queue)
	return args.String(0), args.Error(1)
}

type MockedAqueductClient struct {
	mock.Mock
}

func (m *MockedAqueductClient) ID() string {
	args := m.Called()
	return args.String(0)
}

func (m *MockedAqueductClient) TwirpClient() aqueduct_api_v1.JobQueueService {
	args := m.Called()
	if args.Get(0) == nil {
		return nil
	}
	return args.Get(0).(aqueduct_api_v1.JobQueueService)
}

func (m *MockedAqueductClient) AdminClient() aqueduct_api_v1.AdminService {
	args := m.Called()
	if args.Get(0) == nil {
		return nil
	}
	return args.Get(0).(aqueduct_api_v1.AdminService)
}

func (m *MockedAqueductClient) AuthClient() aqueduct_api_v1.AuthService {
	args := m.Called()
	if args.Get(0) == nil {
		return nil
	}
	return args.Get(0).(aqueduct_api_v1.AuthService)
}

func (m *MockedAqueductClient) MaintenanceClient() aqueduct_maintenance_api_v1.MaintenanceService {
	args := m.Called()
	if args.Get(0) == nil {
		return nil
	}
	return args.Get(0).(aqueduct_maintenance_api_v1.MaintenanceService)
}

func (m *MockedAqueductClient) Send(ctx context.Context, j aqueduct.Job, opts ...aqueduct.SendOption) (string, error) {
	args := m.Called(ctx, j, opts)
	return args.String(0), args.Error(1)
}

func (m *MockedAqueductClient) SendBatch(ctx context.Context, batch []aqueduct.BatchItem) (*aqueduct.SendBatchResult, error) {
	args := m.Called(ctx, batch)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).(*aqueduct.SendBatchResult), args.Error(1)
}

func (m *MockedAqueductClient) Receive(ctx context.Context, app string, queues []string, options aqueduct.ReceiveOptions) (result *aqueduct.ReceiveResult, backoff time.Duration, err error) {
	args := m.Called(ctx, app, queues, options)
	var res *aqueduct.ReceiveResult
	if args.Get(0) != nil {
		res = args.Get(0).(*aqueduct.ReceiveResult)
	}
	return res, args.Get(1).(time.Duration), args.Error(2)
}

func (m *MockedAqueductClient) Heartbeat(ctx context.Context, j aqueduct.Job) error {
	args := m.Called(ctx, j)
	return args.Error(0)
}

func (m *MockedAqueductClient) Ack(ctx context.Context, j aqueduct.Job, status aqueduct.AckStatus) error {
	args := m.Called(ctx, j, status)
	return args.Error(0)
}

func (m *MockedAqueductClient) QueueDepth(ctx context.Context, app, queue string) (int64, error) {
	args := m.Called(ctx, app, queue)
	return args.Get(0).(int64), args.Error(1)
}

func (m *MockedAqueductClient) Peek(ctx context.Context, app, queue string, count int) ([][]byte, error) {
	args := m.Called(ctx, app, queue, count)
	if args.Get(0) == nil {
		return nil, args.Error(1)
	}
	return args.Get(0).([][]byte), args.Error(1)
}
