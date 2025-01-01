package aqueduct

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"time"

	api "github.com/github/aqueduct-client-go/v2/proto"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/twitchtv/twirp"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

type clientConfig struct {
	clientID       string
	http           HTTPClient
	idempotentSend bool
	producerID     string
	logger         log.Logger
	statsConfig    *StatsConfig
	hmacConfig     hmacConfig
	authConfig     authConfig
}
type hmacConfig struct {
	sendHmacSecret     string
	receiveHmacSecrets []string
}

const hmacHeader = "_hmac"

type authConfig struct {
	apiKey          string
	apiKeyVersion   *int
	tokenExpiration time.Duration
	clock           func() time.Time
	authAs          string
}

// ClientOption is the functional option type for configuring a Client.
type ClientOption func(*clientConfig) error

// WithClientID is the ClientOption that sets a Client's ID. It returns an
// error when the string is empty.
func WithClientID(s string) ClientOption {
	return func(c *clientConfig) error {
		if s == "" {
			return errors.New("client ID must be non-empty")
		}
		c.clientID = s
		return nil
	}
}

// defaultClient sets the default client ID.
func defaultClientID() ClientOption {
	return func(c *clientConfig) error {
		hostname, err := os.Hostname()
		if err != nil {
			return fmt.Errorf("could not determine hostname for client id: %s", err)
		}
		pid := os.Getpid()
		c.clientID = fmt.Sprintf("%s:%d", hostname, pid)
		return nil
	}
}

// WithHTTPClient is the ClientOption that overrides the default http.Client
// used by a Client. It returns an error when nil.
func WithHTTPClient(hc *http.Client) ClientOption {
	return func(c *clientConfig) error {
		if hc == nil {
			return errors.New("http client must be non-nil")
		}
		c.http = &defaultHTTPClient{client: hc}
		return nil
	}
}

// WithHTTPClientInterface is the ClientOption that overrides the default
// http.Client used by a client. It returns an error when nil.
func WithHTTPClientInterface(hc HTTPClient) ClientOption {
	return func(c *clientConfig) error {
		if hc == nil {
			return errors.New("http client must be non-nil")
		}
		c.http = hc
		return nil
	}
}

// WithIdempotentSend is the ClientOption that controls a Client's idempotent
// behavior for job Send requests.
func WithIdempotentSend(b bool) ClientOption {
	return func(c *clientConfig) error {
		c.idempotentSend = b
		return nil
	}
}

// WithProducerID is the ClientOption that overrides the default random
// producer ID of a Client used for idempotent send. It returns an error when
// the string is empty.
func WithProducerID(s string) ClientOption {
	return func(c *clientConfig) error {
		if s == "" {
			return errors.New("producer ID must be non-empty")
		}
		c.producerID = s
		return nil
	}
}

// WithClientLogger is the ClientOption that overrides a Client's default
// logger. It returns an error when nil.
func WithClientLogger(l log.Logger) ClientOption {
	return func(c *clientConfig) error {
		if l == nil {
			return errors.New("logger must be non-nil")
		}
		c.logger = l
		return nil
	}
}

// WithClientStats is the ClientOption that overrides a Client's default
// stats.Client with the provided StatsConfig. It returns an error when nil.
func WithClientStats(statsConfig *StatsConfig) ClientOption {
	return func(c *clientConfig) error {
		if statsConfig == nil {
			return errors.New("stats config must be non-nil")
		}
		c.statsConfig = statsConfig
		return nil
	}
}

func WithAPIKey(key string) ClientOption {
	return func(c *clientConfig) error {
		if key == "" {
			return errors.New("API key can't be blank")
		}
		c.authConfig.apiKey = key
		return nil
	}
}

func WithAPIKeyVersion(version int) ClientOption {
	return func(c *clientConfig) error {
		if version < 0 {
			return fmt.Errorf("API key version %d is invalid", version)
		}
		c.authConfig.apiKeyVersion = &version
		return nil
	}
}

func WithAuthAs(authAs string) ClientOption {
	return func(c *clientConfig) error {
		if authAs == "" {
			return errors.New("authAs can't be blank")
		}
		c.authConfig.authAs = authAs
		return nil
	}
}

func WithClock(clock func() time.Time) ClientOption {
	return func(c *clientConfig) error {
		c.authConfig.clock = clock
		return nil
	}
}

// WithSendHmacSecret is the ClientOption that sets the HMAC secret used to sign
// payloads on Send.
func WithSendHmacSecret(secret string) ClientOption {
	return func(c *clientConfig) error {
		if secret == "" {
			return errors.New("Send HMAC secret must be non-empty")
		}
		c.hmacConfig.sendHmacSecret = secret
		return nil
	}
}

// WithReceiveHmacSecrets is the ClientOption that sets the HMAC secrets used to
// validate payloads on Receive. Multiple secrets are allowed to support
// rolling secrets.
func WithReceiveHmacSecrets(secrets []string) ClientOption {
	return func(c *clientConfig) error {
		for _, secret := range secrets {
			if secret == "" {
				return errors.New("Receive HMAC secrets must be non-empty")
			}
		}

		c.hmacConfig.receiveHmacSecrets = secrets
		return nil
	}
}

// Client is an Aqueduct API Twirp client instrumented with stats and logging.
//
// It must be created using NewClient.
type Client interface {
	ID() string
	TwirpClient() api.JobQueueService
	Send(ctx context.Context, j Job, opts ...SendOption) (string, error)
	SendBatch(ctx context.Context, batch []BatchItem) (*SendBatchResult, error)
	Receive(ctx context.Context, app string, queues []string, options ReceiveOptions) (result *ReceiveResult, backoff time.Duration, err error)
	Heartbeat(ctx context.Context, j Job) error
	Ack(ctx context.Context, j Job, status AckStatus) error
	QueueDepth(ctx context.Context, app, queue string) (int64, error)
	Peek(ctx context.Context, app, queue string, count int) ([][]byte, error)
}

type client struct {
	id                    string
	svc                   api.JobQueueService
	adminSvc              api.AdminService
	producer              producer
	logger                log.Logger
	stats                 stats.Client
	hmacConfig            hmacConfig
	defaultWorkerMetadata *WorkerMetadata
}

// NewClient returns a new Client configured with any provided ClientOptions.
func NewClient(addr string, opts ...ClientOption) (Client, error) {
	cfg := clientConfig{
		authConfig: authConfig{
			clock:           time.Now,
			tokenExpiration: 5 * time.Minute,
		},
	}
	opts = append([]ClientOption{defaultClientID()}, opts...)
	for _, o := range opts {
		if err := o(&cfg); err != nil {
			return nil, fmt.Errorf("applying client option: %w", err)
		}
	}
	if addr == "" {
		return nil, errors.New("address must be non-empty")
	}

	if cfg.http == nil {
		cfg.http = newDefaultHTTPClient()
	}

	var p producer = &standardProducer{}
	if cfg.idempotentSend {
		producerID := cfg.producerID
		if producerID == "" {
			generated, err := generateProducerID()
			if err != nil {
				return nil, fmt.Errorf("generating producer ID: %w", err)
			}
			producerID = generated
		}
		p = &idempotentProducer{
			id: producerID,
		}
	}

	logger, err := newClientLogger(cfg.logger)
	logger = logger.WithFields(kvp.String("client_id", cfg.clientID))
	if err != nil {
		return nil, err
	}

	if cfg.statsConfig == nil {
		cfg.statsConfig, _ = NewStatsConfig()
	}

	statsClient, err := cfg.statsConfig.client("aqueduct.client", stats.Tags{})
	if err != nil {
		return nil, fmt.Errorf("creating stats reporter: %w", err)
	}

	protoClient := api.NewJobQueueServiceProtobufClient(
		addr,
		cfg.http,
		twirp.WithClientHooks(newClientHooks(logger, statsClient)),
		twirp.WithClientInterceptors(newAuthInterceptor(cfg.authConfig)),
	)

	adminClient := api.NewAdminServiceProtobufClient(
		addr,
		cfg.http,
		twirp.WithClientHooks(newClientHooks(logger, statsClient)),
		twirp.WithClientInterceptors(newAuthInterceptor(cfg.authConfig)),
	)

	defaultWorkerMetadata := NewWorkerMetadata("")
	return &client{
		id:                    cfg.clientID,
		svc:                   protoClient,
		adminSvc:              adminClient,
		producer:              p,
		logger:                logger,
		stats:                 statsClient,
		hmacConfig:            cfg.hmacConfig,
		defaultWorkerMetadata: &defaultWorkerMetadata,
	}, nil
}

// ID returns the client's ID.
func (c *client) ID() string { return c.id }

// TwirpClient returns the underlying JobQueueService Twirp client.
func (c *client) TwirpClient() api.JobQueueService { return c.svc }

// AdminClient returns the underlying AdminService twirp client
func (c *client) AdminClient() api.AdminService { return c.adminSvc }

// SendOption is the functional option type for configuring a job on Send.
type SendOption func(*api.SendRequest)

// ClientWithJobRedeliveryTimeoutSeconds sets the value for redelivery timeouts on this
// job. The default behavior is to use the server-side default of 10 minutes.
func WithJobRedeliveryTimeoutSeconds(seconds int) SendOption {
	return func(r *api.SendRequest) {
		r.RedeliveryTimeoutSecs = wrapperspb.UInt32(uint32(seconds))
	}
}

// WithJobMaxRedeliveryAttempts sets the value for max redelivery attempts for
// this job.  The first delivery doesn't count against this number. Set to zero
// to disable redelivery attempts.  The default behavior is to use the
// server-side default of 2 redeliveries.
func WithJobMaxRedeliveryAttempts(attempts int) SendOption {
	return func(r *api.SendRequest) {
		r.MaxRedeliveryAttempts = wrapperspb.UInt32(uint32(attempts))
	}
}

// WithSequence sets the ProducerSequence to the input value of seq
// This is useful for ensuring at most once delivery of a single Send with retries.
func WithSequence(seq uint64) SendOption {
	return func(r *api.SendRequest) {
		r.ProducerSequence = seq
	}
}

// WithTTL sets the job TTL.
func WithTTL(ttl time.Duration) SendOption {
	return func(r *api.SendRequest) {
		r.TtlSeconds = wrapperspb.UInt32(uint32(ttl.Seconds()))
	}
}

// Send produces a job. It returns the produced job's ID on success.
//
// It supports idempotent produce behavior when enabled on the client. See the
// WithIdempotentSend option.
func (c *client) Send(ctx context.Context, j Job, opts ...SendOption) (string, error) {
	request := c.createRequest(j, opts)
	resp, err := c.svc.Send(ctx, request)
	if err != nil {
		return "", err
	}
	return resp.JobId, nil
}

func (c *client) createRequest(j Job, opts []SendOption) *api.SendRequest {
	var deliverAt *timestamppb.Timestamp
	if !j.DeliverAt.IsZero() {
		deliverAt = timestamppb.New(j.DeliverAt)
	}

	request := &api.SendRequest{
		App:        j.App,
		Queue:      j.Queue,
		Payload:    j.Payload,
		JobId:      j.ID,
		Headers:    j.Headers,
		ClientId:   c.id,
		ProducerId: c.producer.ID(),
		DeliverAt:  deliverAt,
	}

	for _, opt := range opts {
		opt(request)
	}

	// If ProducerSequence was not explicitly set by a SendOption, then take the default value from the producer
	if request.ProducerSequence == 0 {
		request.ProducerSequence = c.producer.Sequence()
	}

	if c.hmacConfig.sendHmacSecret != "" {
		if request.Headers == nil {
			request.Headers = map[string]string{}
		}
		request.Headers[hmacHeader] = computeHmac(j.Payload, c.hmacConfig.sendHmacSecret)
	}
	return request
}

// SendBatchResponse contains the index of the job in the batch, the job ID, and an error if one occurred
type SendBatchResponse struct {
	Index int
	JobID string
	Error string
}

// SendBatchResult contains a backend name and a list of SendBatchResponses
type SendBatchResult struct {
	BackendName        string
	SendBatchResponses []SendBatchResponse
}

// BatchItem contains a job and a list of SendOptions
type BatchItem struct {
	Job  Job
	Opts []SendOption
}

// SendBatch produces a batch of jobs. It returns a SendBatchResult on success.
func (c *client) SendBatch(ctx context.Context, batch []BatchItem) (*SendBatchResult, error) {
	sr := make([]*api.SendRequest, 0, len(batch))
	for _, bi := range batch {
		request := c.createRequest(bi.Job, bi.Opts)
		sr = append(sr, request)
	}
	sendBatchRequest := &api.SendBatchRequest{SendRequests: sr}
	resp, err := c.svc.SendBatch(ctx, sendBatchRequest)
	if err != nil {
		return nil, err
	}

	responses := make([]SendBatchResponse, 0, len(resp.GetBatchMessageResponses()))

	for _, bmr := range resp.GetBatchMessageResponses() {
		responses = append(responses, SendBatchResponse{
			Index: int(bmr.GetIndex()),
			JobID: bmr.GetJobId(),
			Error: bmr.GetError()})
	}

	return &SendBatchResult{
		BackendName:        resp.GetBackendName(),
		SendBatchResponses: responses}, nil
}

// ReceiveResult contains a successfully received job and its metadata.
type ReceiveResult struct {
	Job
	DeliveryAttempt     int
	MaxDeliveryAttempts int
	SentAt              time.Time
	ValidPayload        bool
}

type ReceiveOptions struct {
	// Timeout controls how long the client will block waiting for a job to become available. This is
	// unrelated to a context or transport timeout.
	//
	// NOTE: Receive timeouts must be shorter than the underlying http.Client's timeout. The default
	// http.Client has a 20s timeout. In order to safely use longer/ receive timeouts, an
	// appropriately configured http.Client must be set using the WithHTTPClient option.
	Timeout time.Duration

	// WorkerID should be unique per worker issuing Receive calls. The worker ID is used for
	// hash-based routing by both aqueduct-gateway and aqueduct. If worker IDs are non-unique,
	// it could cause routing imbalances.
	WorkerID string

	// WorkerPool designates a logical group of workers that work the same queues. The pool value is
	// used to calculate pool metrics in Aqueduct and enable features like execution time throttling.
	WorkerPool string

	// WorkerTags are optional key-values that can be used pause subsets of workers.
	// For example, a "site" tag could be used to pause workers in a single site.
	WorkerTags map[string]string

	// WorkerIdleMs is the amount of time a worker spends not processing jobs. It is the time
	// elapsed between subsequent Receive requests. It is used by Aqueduct to calculate
	// worker utilization metrics and to detect regressions in idle time for worker clients.
	WorkerIdleMs uint64

	// For internal use only
	BypassPausing bool
}

// Receive dequeues a job for an app and queue(s). When multiple queues have jobs available, queue
// order determines priority.
//
// If no jobs are immediately available, the client will block for ReceiveOptions.Timeout. If no
// jobs available within ReceiveOptions.Timeout, Receive will return a nil *ReceiveResult and nil
// error signaling no job was found.
//
// After a successful Receive, the caller is responsible for heartbeating the
// job and ACK'ing it once it's been handled.
func (c *client) Receive(ctx context.Context, app string, queues []string, options ReceiveOptions) (*ReceiveResult, time.Duration, error) {
	if options.Timeout == 0 {
		options.Timeout = defaultReceiveTimeout
	}

	if options.WorkerID == "" {
		options.WorkerID = c.defaultWorkerMetadata.ID
	}

	resp, err := c.svc.Receive(ctx, &api.ReceiveRequest{
		Worker: &api.Worker{
			Id:   options.WorkerID,
			Pool: options.WorkerPool,
			Tags: options.WorkerTags,
		},
		App:           app,
		Queues:        queues,
		TimeoutMs:     int32(options.Timeout / time.Millisecond),
		ClientId:      c.id,
		BypassPausing: options.BypassPausing,
	})
	if err != nil {
		return nil, 0, err
	}

	backoff := time.Duration(resp.BackoffSeconds) * time.Second
	if resp.Queue == "" {
		return nil, backoff, nil // no job available
	}

	return &ReceiveResult{
		Job: Job{
			App:     resp.App,
			Queue:   resp.Queue,
			ID:      resp.JobId,
			Payload: resp.Payload,
			Headers: resp.Headers,
		},
		DeliveryAttempt:     int(resp.DeliveryAttempt),
		MaxDeliveryAttempts: int(resp.MaxDeliveryAttempts),
		SentAt:              resp.SentAt.AsTime(),
		ValidPayload:        c.validateReceive(ctx, resp),
	}, backoff, nil
}

func (c *client) validateReceive(ctx context.Context, resp *api.ReceiveResponse) bool {
	if len(c.hmacConfig.receiveHmacSecrets) == 0 {
		return true
	}

	computed := resp.Headers[hmacHeader]

	for _, secret := range c.hmacConfig.receiveHmacSecrets {
		if computeHmac(resp.Payload, secret) == computed {
			return true
		}
	}

	return false
}

// Heartbeat attempts to send a heartbeat for a received job.
//
// If the time since the last heartbeat (or first heartbeat post-delivery)
// exceeds a job's delivery timeout it will be considered timed out. Eligible
// timed out jobs (haven't exceeded their max delivery attempts) may be
// redelivered.
func (c *client) Heartbeat(ctx context.Context, j Job) error {
	_, err := c.svc.Heartbeat(ctx, &api.HeartbeatRequest{
		App:      j.App,
		Queue:    j.Queue,
		JobId:    j.ID,
		ClientId: c.id,
	})
	return err
}

// AckStatus represents the status for acknowledging a job after handling.
type AckStatus int

const (
	// AckSuccess states that a job was handled successfully.
	AckSuccess = AckStatus(1)

	// AckFailure stats that a job was not handled successfully.
	AckFailure = AckStatus(2)
)

func (as AckStatus) String() string {
	switch as {
	case AckSuccess:
		return "success"
	case AckFailure:
		return "failure"
	default:
		return "invalid"
	}
}

// Ack acknowledges that a delivered job has been handled with the provided
// status. Calls to Ack terminate a job's lifecycle regardless of provided
// status. Successfully handled jobs must be ack'd to ensure they're not
// redelivered.
func (c *client) Ack(ctx context.Context, j Job, status AckStatus) error {
	_, err := c.svc.Ack(ctx, &api.AckRequest{
		App:      j.App,
		Queue:    j.Queue,
		JobId:    j.ID,
		Status:   api.AckRequest_Status(status),
		ClientId: c.id,
	})
	return err
}

// QueueDepth gets the depth of the given queue
func (c *client) QueueDepth(ctx context.Context, app, queue string) (int64, error) {
	resp, err := c.svc.QueueDepth(ctx, &api.QueueDepthRequest{
		App:   app,
		Queue: queue,
	})
	if err != nil {
		return 0, err
	}
	return resp.Depth, nil
}

// Peek returns a slice of payloads for the first N jobs at the head of a queue
// based on the order they would be received. As a limitation of the peek API,
// the response does not include any job metadata, only their payloads.
//
// It returns a nil slice when the queue is empty.
//
// Calls to Peek do not dequeue jobs or affect their delivery in any way.
func (c *client) Peek(ctx context.Context, app, queue string, count int) ([][]byte, error) {
	resp, err := c.svc.Peek(ctx, &api.PeekRequest{
		App:   app,
		Queue: queue,
		Count: int32(count),
	})
	if err != nil {
		return nil, err
	}

	return resp.GetPayloads(), nil
}

func (c *client) DefaultWorkerID() string {
	return c.defaultWorkerMetadata.ID
}
