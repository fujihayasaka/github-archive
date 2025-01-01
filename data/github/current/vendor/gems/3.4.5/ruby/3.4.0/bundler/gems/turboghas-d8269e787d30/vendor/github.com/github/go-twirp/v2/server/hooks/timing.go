package hooks

import (
	"context"
	"time"

	"github.com/twitchtv/twirp"
)

// RequestRoutedDurationLabel is the label used for the request_routed_duration metric.
const RequestRoutedDurationLabel = "request_routed_duration"

// RequestDurationLabel is the label used for the request_duration metric.
const RequestDurationLabel = "request_duration"

// RequestCountLabel is the label used for the request_count metric.
const RequestCountLabel = "request_count"

// ResponsePreparedDurationLabel is the label used for the response_prepared_duration metric.
const ResponsePreparedDurationLabel = "response_prepared_duration"

// ResponseSentDurationLabel is the label used for the response_sent_duration metric.
const ResponseSentDurationLabel = "response_sent_duration"

type ctxTiming struct{}

type times struct {
	requestReceived  time.Time
	requestRouted    time.Time
	responsePrepared time.Time
	responseSent     time.Time
}

// TimingHooks record the time at which each hook occurs and store them in the Context to be used
// when calculating timing statistics.
func TimingHooks() *twirp.ServerHooks {
	// The usage of the times depends on the fact that these hooks will always be executed in order.
	return &twirp.ServerHooks{
		RequestReceived: func(ctx context.Context) (context.Context, error) {
			return context.WithValue(ctx, ctxTiming{}, &times{requestReceived: time.Now()}), nil
		},
		RequestRouted: func(ctx context.Context) (context.Context, error) {
			getTimes(ctx).requestRouted = time.Now()
			return ctx, nil
		},
		ResponsePrepared: func(ctx context.Context) context.Context {
			getTimes(ctx).responsePrepared = time.Now()
			return ctx
		},
		ResponseSent: func(ctx context.Context) {
			getTimes(ctx).responseSent = time.Now()
		},
	}
}

func getTimes(ctx context.Context) *times {
	if times, ok := ctx.Value(ctxTiming{}).(*times); ok {
		return times
	}
	panic("timing data was accessed before being initialized. Ensure that your TimingHooks are " +
		"EARLIER in the chain than anything that accesses them.")
}

// RoutingDuration calculates the duration of time that it took to route the request. This is
// calculated as the time between when the request was received and when it was routed.
func RoutingDuration(ctx context.Context) time.Duration {
	return getTimes(ctx).requestRouted.Sub(getTimes(ctx).requestReceived)
}

// ResponsePreparationDuration calculates the duration of time that it took to prepare the
// response. This is calculated as the time between the request being routed and the response being
// prepared.
func ResponsePreparationDuration(ctx context.Context) time.Duration {
	if dur := getTimes(ctx).responsePrepared; !dur.IsZero() {
		return dur.Sub(getTimes(ctx).requestRouted)
	}
	return 0
}

// ResponseSendingDuration calculates the duration of time that it took to send the response to the
// client.  This is calculated as the time between when the response was prepared and when it was
// completely sent.
func ResponseSendingDuration(ctx context.Context) time.Duration {
	if prep := getTimes(ctx).responsePrepared; !prep.IsZero() {
		return getTimes(ctx).responseSent.Sub(prep)
	}
	return 0
}

// RequestDuration calculates the total duration of time that was spent processing the request.
// This is calculated as the time between the request being received and the response being sent.
func RequestDuration(ctx context.Context) time.Duration {
	return getTimes(ctx).responseSent.Sub(getTimes(ctx).requestReceived)
}
