package aqueduct

import (
	"context"
	"sync"
	"time"

	"github.com/github/aqueduct-client-go/v3/pkg/aqueduct"
	api "github.com/github/aqueduct-client-go/v3/proto"
	maintapi "github.com/github/aqueduct-client-go/v3/proto/maintenance"
	"github.com/github/sweagentd/internal/observability"
	"github.com/google/uuid"
)

// MemoryClient provides an in-memory implementation of AqueductClient for testing.
type MemoryClient struct {
	Client

	queue *memoryQueue
}

// NewMemoryClient creates a new in-memory Aqueduct client for testing.
func NewMemoryClient(obsv observability.Exporters) *MemoryClient {
	queue := memoryQueue{
		jobs: make(map[string]map[string][]*aqueduct.Job),
	}
	return &MemoryClient{
		Client: Client{
			appName:       "test-app",
			aqueductURL:   "http://localhost:8080",
			apiKey:        "test-api-key",
			apiKeyVersion: 1,
			obsv:          obsv,
			client:        &queue,
		},
		queue: &queue,
	}
}

// QueuedJobs returns all jobs queued for the specified queues.
func (ac *MemoryClient) QueuedJobs(queues ...string) []*aqueduct.Job {
	var aqueductJobs []*aqueduct.Job
	for _, queue := range queues {
		aqueductJobs = append(aqueductJobs, ac.queue.QueuedJobs(ac.AppName(), queue)...)
	}
	return aqueductJobs
}

type memoryQueue struct {
	mu   sync.RWMutex
	jobs map[string]map[string][]*aqueduct.Job
}

var _ aqueduct.Client = &memoryQueue{}

func (c *memoryQueue) ID() string { return "client-id" }

func (c *memoryQueue) TwirpClient() api.JobQueueService { return nil }

func (c *memoryQueue) AdminClient() api.AdminService { return nil }

func (c *memoryQueue) AuthClient() api.AuthService { return nil }

func (c *memoryQueue) MaintenanceClient() maintapi.MaintenanceService { return nil }

func (c *memoryQueue) Send(ctx context.Context, j aqueduct.Job, opts ...aqueduct.SendOption) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if _, ok := c.jobs[j.App]; !ok {
		c.jobs[j.App] = make(map[string][]*aqueduct.Job)
	}

	if _, ok := c.jobs[j.App][j.Queue]; !ok {
		c.jobs[j.App][j.Queue] = []*aqueduct.Job{}
	}

	if j.ID == "" {
		j.ID = uuid.NewString()
	}

	if j.DeliverAt.IsZero() {
		j.DeliverAt = time.Now()
	}

	c.jobs[j.App][j.Queue] = append(c.jobs[j.App][j.Queue], &j)

	return j.ID, nil
}

func (c *memoryQueue) SendBatch(ctx context.Context, batch []aqueduct.BatchItem) (*aqueduct.SendBatchResult, error) {
	return nil, nil
}

func (c *memoryQueue) Receive(ctx context.Context, app string, queues []string, options aqueduct.ReceiveOptions) (*aqueduct.ReceiveResult, time.Duration, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	queue := queues[0] // For simplicity, we only handle one queue at a time.
	resp, ok := c.jobs[app][queue]
	if !ok || len(resp) == 0 {
		return nil, 0, nil
	}

	// Pop the first job from the queue.
	job := resp[0]
	c.jobs[app][queue] = resp[1:]

	backoff := time.Duration(5) * time.Second

	return &aqueduct.ReceiveResult{
		Job:                 *job,
		DeliveryAttempt:     1,
		MaxDeliveryAttempts: 2,
		SentAt:              job.DeliverAt,
		ValidPayload:        true,
	}, backoff, nil
}

func (c *memoryQueue) Heartbeat(ctx context.Context, j aqueduct.Job) error { return nil }

func (c *memoryQueue) HeartbeatWithTimeout(ctx context.Context, j aqueduct.Job, timeout time.Duration) error {
	return nil
}

func (c *memoryQueue) Ack(ctx context.Context, j aqueduct.Job, status aqueduct.AckStatus) error {
	return nil
}

func (c *memoryQueue) QueueDepth(_ context.Context, app, queue string) (int64, error) {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return int64(len(c.jobs[app][queue])), nil
}

func (c *memoryQueue) Peek(ctx context.Context, app, queue string, count int) ([][]byte, error) {
	return nil, nil
}

func (c *memoryQueue) QueuedJobs(app, queue string) []*aqueduct.Job {
	c.mu.RLock()
	defer c.mu.RUnlock()

	if _, ok := c.jobs[app]; !ok {
		return nil
	}

	if _, ok := c.jobs[app][queue]; !ok {
		return nil
	}

	return c.jobs[app][queue]
}
