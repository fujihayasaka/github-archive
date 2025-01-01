package retries

import (
	"context"
	"crypto/rand"
	"math"
	"math/big"
	"time"

	clockpkg "github.com/benbjohnson/clock"
	ghaqueduct "github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
	"google.golang.org/protobuf/proto"

	"github.com/github/notifyd/internal/pkg/aqueduct"
	"github.com/github/notifyd/internal/pkg/compress"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/job"
	"github.com/github/notifyd/internal/pkg/job/middlewares/retries/retriables"
	"github.com/github/notifyd/internal/pkg/tenancy"
)

// ErrRetriesExpired is returned whenever a message expires all its retries.
var ErrRetriesExpired = errors.New("retries expired")

// AqueductRetrier takes an unmarshaled hydro message and enqueues it for redelivery using an exponential
// backoff algorithm with some jitter.
type AqueductRetrier struct {
	cfg     Config
	telem   *telemetry.Provider
	client  aqueduct.Sender
	statter stats.Client
	clock   clockpkg.Clock
}

// NewAqueductRetrier creates a new AqueductRetrier.
func NewAqueductRetrier(cfg Config, clock clockpkg.Clock, telem *telemetry.Provider, client aqueduct.Sender, statter stats.Client) *AqueductRetrier {
	return &AqueductRetrier{
		cfg:     cfg,
		clock:   clock,
		telem:   telem,
		statter: statter,
		client:  client,
	}
}

// Retry enqueues the given message for redelivery. For that uses the retry method, which is
// generated based on the options passed to the retries/gen package...
func (r *AqueductRetrier) Retry(ctx context.Context, tenant tenancy.Tenant, rawMsg []byte) error {
	logger := r.telem.Logger.WithContext(ctx).WithFields(kvp.String("ctx", "retrier"))
	var envelope hydro_pb.Envelope
	if err := proto.Unmarshal(rawMsg, &envelope); err != nil {
		return err
	}

	logger = logger.WithFields(kvp.String("gh.notifyd.message.type_url", envelope.TypeUrl))
	logger.Info("sending retry message")
	defer logger.Info("retry message sent")

	retriableMsg, err := retriables.BuildMessage(&envelope)
	if err != nil {
		return err
	}

	return r.sendRetry(ctx, tenant, retriableMsg)
}

func (r *AqueductRetrier) sendRetry(ctx context.Context, tenant tenancy.Tenant, msg retriables.Message) error {
	logger := r.telem.Logger.WithContext(ctx).WithFields(kvp.String("ctx", "retrier"))

	logger.Debug("updating retries")
	msg.UpdateRetries()
	if r.shouldHalt(msg) {
		statsCount(r.statter, msg, statsProcessed, statsFailed)
		return errors.Wrapf(ErrRetriesExpired, "attempts %d, limit %d", msg.GetAttempts(), r.cfg.MaxAttempts)
	}
	logger.Debug("encoding retry message")
	content, err := msg.Encode()
	if err != nil {
		return errors.Wrap(err, "encoding retry message")
	}
	payload, err := aqueduct.NewPayloadFromBytes(content, aqueduct.WithCompressedPayload(compress.Deflate, logger))
	if err != nil {
		return errors.Wrap(err, "generating payload from message")
	}

	otelHeaders := make(map[string]string)
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(otelHeaders))

	headers := job.NewHeaders(
		job.WithDefaultSenderHeaders(ctx),
		job.WithContentLengthHeader(payload.Len()),
		job.WithContentEncodingHeader(payload.Encoding()),
		job.WithTenantHeaders(tenant),
		job.WithHeadersFromMap(otelHeaders),
	)

	logger.Debug("calculating backoff")
	deliverAt, err := r.deliverAt(ctx, msg)
	if err != nil {
		return errors.Wrap(err, "calculating backoff")
	}

	aqueductJob := ghaqueduct.Job{
		App:       r.cfg.AqueductApp,
		Queue:     msg.Queue(),
		Payload:   payload.Content(),
		DeliverAt: deliverAt,
		Headers:   headers.IntoMap(),
	}

	logger.Debug("sending aqueduct request")
	id, err := r.client.Send(ctx, aqueductJob)
	if err != nil {
		logger.WithError(err).Error("can't enqueue redeliver")
		statsCount(r.statter, msg, statsEnqueued, statsFailed)
		return err
	}

	fields := headers.ToLog()
	fields = append(fields,
		kvp.Int("gh.notifyd.retry.attempts", int(msg.GetAttempts())),
		kvp.String("gh.aqueduct.job.id", id),
	)
	logger.Info("retry enqueued to aqueduct", fields...)
	statsCount(r.statter, msg, statsEnqueued, statsSuccess)
	return nil
}

// shouldHalt returns whether retries need to stop for a given attempt number. It is based on the
// configuration for the max number of attempts.
func (r *AqueductRetrier) shouldHalt(msg retriables.Message) bool {
	attempt := msg.GetAttempts()
	return attempt > r.cfg.MaxAttempts
}

// deliverAt will apply a factor to the configured base backoff based on powers of 2 + a jitter that
// is factor * 0.1 * base.
//
// All parameters on this algorithm can be adapted through config.Config
func (r *AqueductRetrier) deliverAt(ctx context.Context, msg retriables.Message) (time.Time, error) {
	attempt := msg.GetAttempts()

	baseBackoff := float64(r.cfg.BaseBackoff)
	baseFactor := r.cfg.ExponentialFactor
	baseJitter := r.cfg.JitterFactor

	// factor depends on the attempt number and makes the wait time bigger per attempt
	factor := math.Pow(baseFactor, float64(attempt))

	// jitterFactor applies randomization to the backoff so that in case if many at the same time they
	// are not all enqueued one after the other
	jitterFactor, err := generateJitterFactor(baseJitter, factor)
	if err != nil {
		return time.Time{}, err
	}

	// backoff is the actual calculated number of nanoseconds that we will wait for the next retry to
	// happen.
	backoff := baseBackoff*factor + jitterFactor*baseBackoff
	r.telem.Logger.WithContext(ctx).
		WithFields(
			kvp.String("ctx", "retrier"),
			kvp.Duration("gh.notifyd.retry.backoff", time.Duration(backoff)),
		).
		Info("calculated backoff")

	return r.clock.Now().Add(time.Duration(backoff)), nil
}

// generateJitterFactor generates a random jitter factor
func generateJitterFactor(baseJitter, factor float64) (float64, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return 0, err
	}
	return (float64(n.Int64()) / 1000000) * baseJitter * factor, nil
}
