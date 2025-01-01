// Package processor contains hydro processing functions.
package processor

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"

	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/headers"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	v1 "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	advancedSecurityBillingv0 "github.com/github/hydro-schemas-go/hydro/schemas/advanced_security_billing/v0"
	billingplatformv1 "github.com/github/hydro-schemas-go/hydro/schemas/billingplatform/v1"
	enterprisev0 "github.com/github/hydro-schemas-go/hydro/schemas/github/enterprise_account/v0"
	securitycenterv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/security_center/v0"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	v0 "github.com/github/hydro-schemas-go/hydro/schemas/turboghas/v0"
	"github.com/github/turboghas/internal/data"
	"github.com/github/turboghas/internal/fields"
	"github.com/github/turboghas/internal/fromctx"
	twirpTurboghas "github.com/github/turboghas/internal/monolith_twirp/turboghas/v1"
	"github.com/github/turboghas/internal/resync"
	"github.com/github/turboghas/internal/twirperr"
	"github.com/pkg/errors"
	"github.com/simon-engledew/ctxkey"
	"github.com/twitchtv/twirp"
	"golang.org/x/exp/maps"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/reflect/protoregistry"
)

type Dependencies interface {
	PostReceiveDependencies
}

var topics = make(map[string]struct{})
var lowPriorityTopics = make(map[string]struct{})
var cacheInvalidationTopics = make(map[string]struct{})
var ignoreReplicationLagTopics = make(map[string]struct{})
var queues = make(map[string]struct{})

func Topics() []string {
	return maps.Keys(topics)
}

func CacheInvalidationTopics() []string {
	return maps.Keys(cacheInvalidationTopics)
}

func LowPriorityTopics() []string {
	return maps.Keys(lowPriorityTopics)
}

func IgnoreReplicationLagTopics() []string {
	return maps.Keys(ignoreReplicationLagTopics)
}

func Queues() []string {
	return maps.Keys(queues)
}

func CacheInvalidationTopic(name string) string {
	cacheInvalidationTopics[name] = struct{}{}
	return name
}

func Topic(name string) string {
	topics[name] = struct{}{}
	return name
}

func LowPriorityTopic(name string) string {
	lowPriorityTopics[name] = struct{}{}
	return name
}

func IgnoreReplicationLagTopic(name string) string {
	ignoreReplicationLagTopics[name] = struct{}{}
	return name
}

func queueForMessage(msg proto.Message) string {
	return fmt.Sprintf("turboghas_%s", msg.ProtoReflect().Descriptor().Name())
}

func Queue(msg proto.Message) string {
	name := queueForMessage(msg)
	queues[name] = struct{}{}
	return name
}

type Publisher interface {
	Publish(m protoreflect.ProtoMessage, opts ...hydro.PublishOption) error
}

type Reporter interface {
	Report(ctx context.Context, exception error, payload map[string]string) error
}

type Processor struct {
	sync      *resync.Sync
	db        *data.Data
	githubAPI twirpTurboghas.TurboghasAPI
	deps      Dependencies
	aqueduct  AqueductClient
	publisher Publisher
}

type cacheValue struct {
	until time.Time
	value int64
}

type queueDepthCacher struct {
	AqueductClient
	cache map[string]cacheValue
	ttl   time.Duration
}

// NewQueueDepthCache returns an AqueductClient that will cache QueueDepth responses with a TTL.
func NewQueueDepthCache(client AqueductClient, ttl time.Duration) AqueductClient {
	if client == nil {
		return nil
	}
	return &queueDepthCacher{
		AqueductClient: client,
		cache:          map[string]cacheValue{},
		ttl:            ttl,
	}
}

func (q *queueDepthCacher) QueueDepth(ctx context.Context, appName, queue string) (int64, error) {
	if v, ok := q.cache[queue]; ok && time.Until(v.until) > 0 {
		return v.value, nil
	}
	depth, err := q.AqueductClient.QueueDepth(ctx, appName, queue)
	if err == nil {
		q.cache[queue] = cacheValue{
			until: time.Now().Add(q.ttl),
			value: depth,
		}
	}
	return depth, err
}

func New(db *data.Data, githubAPI twirpTurboghas.TurboghasAPI, publisher Publisher, aqueduct AqueductClient, deps Dependencies) *Processor {
	return &Processor{
		sync:      resync.New(db, githubAPI),
		db:        db,
		githubAPI: githubAPI,
		deps:      deps,
		publisher: publisher,
		aqueduct:  NewQueueDepthCache(aqueduct, 250*time.Millisecond),
	}
}

func (p *Processor) PublishMessage(ctx context.Context, msg proto.Message) error {
	if p.publisher == nil {
		// if no publisher is available, process synchronously
		return p.ProcessMessage(ctx, msg)
	}

	return errors.Wrap(p.publisher.Publish(msg), "failed to publish message")
}

const hydroTopicHeader = "Hydro-Topic"
const hydroOffsetHeader = "Hydro-Offset"
const hydroPartitionHeader = "Hydro-Partition"
const hydroTypeUrlHeader = "Hydro-TypeUrl"

func JobHeaders(ctx context.Context, msg proto.Message) map[string]string {
	out := map[string]string{
		"Content-Type":    "application/protobuf",
		MessageNameHeader: string(proto.MessageName(msg)),
	}
	if outer := Hydro.Value(ctx); outer != nil {
		out[hydroTopicHeader] = outer.Topic
		out[hydroTypeUrlHeader] = outer.TypeUrl
		out[hydroOffsetHeader] = strconv.FormatInt(outer.Offset, 10)
		out[hydroPartitionHeader] = strconv.FormatInt(int64(outer.Partition), 10)
	}

	if slug := tenant.GetTenant(ctx); slug != "" {
		out[headers.Tenant] = slug
	}
	if tenantID := tenant.GetTenantID(ctx); tenantID != "" {
		out[headers.TenantID] = tenantID
	}
	return out
}

func (p *Processor) EnqueueJob(ctx context.Context, msg proto.Message, maxQueueDepth int64) error {
	payload, marshalErr := proto.Marshal(msg)
	if marshalErr != nil {
		return marshalErr
	}

	queue := queueForMessage(msg)

	if _, ok := queues[queue]; !ok {
		return errors.Errorf("queue %s not configured", queue)
	}

	const queueAppName = "turboghas"

	job := aqueduct.Job{
		App:     queueAppName,
		Queue:   queue,
		Payload: payload,
		Headers: JobHeaders(ctx, msg),
	}

	if p.aqueduct == nil || maxQueueDepth == 0 {
		// run the job synchronously
		return p.ProcessJob(ctx, &job)
	}

	depth, depthErr := p.aqueduct.QueueDepth(ctx, queueAppName, queue)
	if depthErr != nil || depth >= maxQueueDepth {
		fromctx.Logger.Value(ctx).WithError(depthErr).Error("running job synchronously", kvp.String("queue", queue))
		fromctx.Statter.Value(ctx).Counter("queue_stalled", stats.Tags{"queue": queue}, 1)
		// We want processing to switch to running synchronously if too much work is on the Aqueduct
		// queue / it is not responding to depth requests (suggesting a possible availability incident).
		// TurboGHAS jobs must be safe to run out of order for this to work.
		return p.ProcessJob(ctx, &job)
	}

	// if this job fails to complete the worker will not nack it
	// instead it will be retried after 6 minutes up to 30 times (3 hours)
	jobID, enqueueErr := p.aqueduct.Send(ctx, job, aqueduct.WithJobRedeliveryTimeoutSeconds(int((6 * time.Minute).Seconds())), aqueduct.WithJobMaxRedeliveryAttempts(30))
	if enqueueErr == nil {
		fromctx.Logger.Value(ctx).Debug("queued job",
			kvp.String("queue", queue),
			kvp.String("job_id", jobID),
		)
	}

	// immediately process any messages that Aqueduct will not enqueue
	// we could also potentially discard them or break them up
	if twirperr.IsTwirpError(enqueueErr, twirp.InvalidArgument) {
		// report that we had to resort to a synchronous run
		fromctx.ExceptionReporter.Report(ctx, enqueueErr, nil)
		fromctx.Logger.Value(ctx).WithError(enqueueErr).Error("could not queue message", kvp.String("queue", queue))
		fromctx.Statter.Value(ctx).Counter("enqueue_failed", stats.Tags{"queue": queue}, 1)

		// run the job synchronously
		// ignore any errors as we cannot afford to keep retrying the job
		jobErr := p.ProcessJob(ctx, &job)
		if jobErr != nil {
			fromctx.ExceptionReporter.Report(ctx, jobErr, nil)
			fromctx.Logger.Value(ctx).WithError(jobErr).Error("could not process synchronously", kvp.String("queue", queue))
		}

		return nil
	}

	return enqueueErr
}

const MessageNameHeader = "MessageName"

func unwrapJob(job *aqueduct.Job) (proto.Message, error) {
	messageName := protoreflect.FullName(job.Headers[MessageNameHeader])
	if !messageName.IsValid() {
		return nil, errors.Errorf("invalid message name %v", messageName)
	}

	messageType, err := protoregistry.GlobalTypes.FindMessageByName(messageName)
	if err != nil {
		return nil, errors.Wrapf(err, "unknown message type %q", messageName)
	}

	inner := messageType.New().Interface()

	var unmarshalOptions interface {
		Unmarshal(b []byte, m proto.Message) error
	} = protojson.UnmarshalOptions{DiscardUnknown: true}

	if contentType, ok := job.Headers["Content-Type"]; ok && contentType == "application/protobuf" {
		unmarshalOptions = proto.UnmarshalOptions{DiscardUnknown: true}
	}

	if unmarshalErr := unmarshalOptions.Unmarshal(job.Payload, inner); unmarshalErr != nil {
		return nil, errors.Wrapf(unmarshalErr, "failed to unmarshal %T", inner)
	}

	return inner, nil
}

func (p *Processor) ProcessJob(ctx context.Context, job *aqueduct.Job) (err error) {
	defer func() {
		if err != nil && !fromctx.IsShuttingDown(ctx) {
			fromctx.Logger.Value(ctx).WithError(err).Error("error in ProcessJob", fields.From(err)...)
		}
	}()

	message, err := unwrapJob(job)
	if err != nil {
		return errors.Wrap(err, "could not unwrap job")
	}

	ctx = WithRequestID(ctx, message)

	switch msg := message.(type) {
	case *githubv1.PostReceive:
		postReceiveErr := p.postReceiveJob(ctx, msg)
		fromctx.SLOTracker.Track(ctx, "availability/online-processor", postReceiveErr == nil)
		return postReceiveErr
	case *githubv1.MembershipUpdate:
		return p.membershipUpdateJob(ctx, msg)
	case *advancedSecurityBillingv0.BillingToggled:
		return p.billingToggledJob(ctx, msg)
	}

	return errors.Errorf("no process method for %s", job.Queue)
}

func UnwrapAqueduct(next func(ctx context.Context, job *aqueduct.Job) error) func(context.Context, aqueduct.ReceiveResult) error {
	return func(ctx context.Context, rr aqueduct.ReceiveResult) error {
		topic := rr.Job.Headers[hydroTopicHeader]
		offset := rr.Job.Headers[hydroOffsetHeader]
		partition := rr.Job.Headers[hydroPartitionHeader]
		messageType := rr.Job.Headers[hydroTypeUrlHeader]

		logger := fromctx.Logger.Value(ctx).WithFields(
			kvp.String("queue", rr.Queue),
			kvp.String("job_id", rr.ID),
			kvp.Int("delivery_attempt", rr.DeliveryAttempt),
			kvp.Time("sent_at", rr.SentAt),
			kvp.String("gh.hydro.topic", topic),
			kvp.String("gh.hydro.offset", offset),
			kvp.String("gh.hydro.partition", partition),
		)
		statter := fromctx.Statter.Value(ctx).WithTags(stats.Tags{
			"type":         "job",
			"queue":        rr.Queue,
			"message_type": messageType,
			"partition":    partition,
		})

		ctx = fromctx.Statter.With(fromctx.Logger.With(ctx, logger), statter)
		ctx = fromctx.ExceptionReporterPayload.With(ctx, map[string]string{
			"gh.aqueduct.job.id":           rr.ID,
			"gh.aqueduct.queue.name":       rr.Queue,
			"gh.aqueduct.delivery_attempt": strconv.Itoa(rr.DeliveryAttempt),
			"gh.hydro.topic":               topic,
			"gh.hydro.offset":              offset,
			"gh.hydro.partition":           partition,
		})

		return next(ctx, &rr.Job)
	}
}

type HydroContext struct {
	Topic     string
	Partition int32
	Offset    int64
	TypeUrl   string
}

var Hydro = ctxkey.New[*HydroContext](nil)

func UnwrapMessage(next func(context.Context, *v1.Envelope) error) func(context.Context, hydro.Message) error {
	return func(ctx context.Context, outer hydro.Message) error {
		logger := fromctx.Logger.Value(ctx).WithFields(
			kvp.Int64("gh.hydro.inner.offset", outer.Offset),
			kvp.Int32("gh.hydro.inner.partition", outer.Partition),
			kvp.String("gh.hydro.inner.topic", outer.Topic),
		)

		ctx = fromctx.ExceptionReporterPayload.With(ctx, map[string]string{
			"gh.hydro.inner.topic":     outer.Topic,
			"gh.hydro.inner.partition": fmt.Sprintf("%d", outer.Partition),
			"gh.hydro.inner.offset":    fmt.Sprintf("%d", outer.Offset),
		})
		// Multi-Tenancy in Proxima requires using a "X-GitHub-Tenant" or "X-GitHub-Tenant-ID" request header across services
		if v := outer.Headers[headers.Tenant]; v != "" {
			ctx = tenant.TenantContext(ctx, v)
		}
		if v := outer.Headers[headers.TenantID]; v != "" {
			ctx = tenant.TenantIDContext(ctx, v)
		}

		var envelope v1.Envelope
		if err := proto.Unmarshal(outer.Value, &envelope); err != nil {
			return err
		}

		logger = logger.WithFields(
			kvp.String("message_id", envelope.Id),
			kvp.String("message_type", envelope.TypeUrl),
			kvp.Time("message_time", envelope.Timestamp.AsTime()),
		)

		statter := fromctx.Statter.Value(ctx).WithTags(stats.Tags{
			"type":         "message",
			"message_type": envelope.TypeUrl,
			"partition":    strconv.FormatInt(int64(outer.Partition), 10),
		})

		ctx = fromctx.Statter.With(fromctx.Logger.With(ctx, logger), statter)
		ctx = Hydro.With(ctx, &HydroContext{
			Topic:     outer.Topic,
			Partition: outer.Partition,
			Offset:    outer.Offset,
			TypeUrl:   envelope.TypeUrl,
		})

		return next(ctx, &envelope)
	}
}

func UnwrapEnvelope(next func(context.Context, proto.Message) error) func(context.Context, *v1.Envelope) error {
	return func(ctx context.Context, envelope *v1.Envelope) error {
		messageType, err := protoregistry.GlobalTypes.FindMessageByURL(envelope.TypeUrl)
		if err != nil {
			return errors.Wrapf(err, "unknown message type %s", envelope.TypeUrl)
		}

		inner := messageType.New().Interface()
		if unmarshalErr := proto.Unmarshal(envelope.Message, inner); unmarshalErr != nil {
			return errors.Wrapf(unmarshalErr, "failed to unmarshal %s", envelope.TypeUrl)
		}

		return next(ctx, inner)
	}
}

func WithRequestID(ctx context.Context, message proto.Message) context.Context {
	if msg, ok := message.(interface {
		GetRequestContext() *entities.RequestContext
	}); ok {
		return requestid.WithGitHubRequestID(ctx, msg.GetRequestContext().GetRequestId())
	}
	return ctx
}

func (p *Processor) ProcessMessage(ctx context.Context, message proto.Message) (err error) {
	defer func() {
		if err != nil && !fromctx.IsShuttingDown(ctx) {
			if _, ok := message.(*githubv1.PostReceive); ok {
				fromctx.SLOTracker.Track(ctx, "availability/online-processor", false)
			}
			fromctx.Logger.Value(ctx).WithError(err).Error("error in ProcessMessage", fields.From(err)...)
		}
	}()

	ctx = WithRequestID(ctx, message)

	switch msg := message.(type) {
	case *githubv1.RepositoryTransfer:
		return p.repositoryTransfer(ctx, msg)
	case *githubv1.RepositoryInvite:
		return p.repositoryInvite(ctx, msg)
	case *githubv1.RepositoryBulkInvite:
		return p.repositoryBulkInvite(ctx, msg)
	case *githubv1.RepositoryAddMember:
		return p.repositoryAddMember(ctx, msg)
	case *githubv1.RepositoryRename:
		return p.repositoryRename(ctx, msg)
	case *githubv1.RepositoryRestored:
		return p.repositoryRestored(ctx, msg)
	case *githubv1.RepositoryDeleted:
		return p.repositoryDeleted(ctx, msg)
	case *githubv1.PostReceive:
		postReceiveErr := p.postReceive(ctx, msg)
		if postReceiveErr != nil && !fromctx.IsShuttingDown(ctx) {
			fromctx.SLOTracker.Track(ctx, "availability/online-processor", false)
		}
		return postReceiveErr
	case *v0.BillableContribution:
		return p.billableContribution(ctx, msg)
	case *githubv1.RepositoryArchivedStatusChanged:
		return p.repositoryArchivedStatusChanged(ctx, msg)
	case *githubv1.RepositoryVisibilityChanged:
		return p.repositoryVisibilityChanged(ctx, msg)
	case *githubv1.MembershipUpdate:
		return p.membershipUpdate(ctx, msg)
	case *enterprisev0.OrganizationAdd:
		return p.organizationAdd(ctx, msg)
	case *enterprisev0.OrganizationUpgrade:
		return p.organizationUpgrade(ctx, msg)
	case *enterprisev0.OrganizationRemove:
		return p.organizationRemove(ctx, msg)
	case *enterprisev0.OrganizationTransfer:
		return p.organizationTransfer(ctx, msg)
	case *githubv1.OrganizationCancelInvitation:
		return p.organizationCancelInvitation(ctx, msg)
	case *githubv1.OrganizationInviteMember:
		return p.organizationInviteMember(ctx, msg)
	case *githubv1.AccountRename:
		return p.accountRename(ctx, msg)
	case *githubv1.UserDestroy:
		return p.userDestroy(ctx, msg)
	case *securitycenterv0.AdvancedSecurityToggled:
		return p.advancedSecurityToggled(ctx, msg)
	case *advancedSecurityBillingv0.BillingToggled:
		return p.billingToggled(ctx, msg)
	case *billingplatformv1.Usage:
		return p.meteredUsage(ctx, msg)
	}

	return errors.Errorf("no process method for %T", message)
}
