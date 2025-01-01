package client

import (
	"context"
	"errors"
	"time"

	"github.com/github/authzd/pkg/capevaluator"
	"github.com/github/authzd/pkg/enumerator"
	"github.com/github/authzd/pkg/proto"
	"github.com/github/go-stats"
)

const (
	requestsMetric   = "authzd.client.request"
	timingMetric     = "authzd.client.timing"
	timingMetaMetric = "authzd.client.statter.timing"
	serverError      = "go-error"
)

func WithStatter(statter stats.Client, clientID string) Option {
	return WithMiddleware(func(client Client) (Client, error) {
		return newStatterMiddleware(clientID, client, statter)
	})
}

func newStatterMiddleware(clientID string, delegate Client, statter stats.Client) (Client, error) {
	if clientID == "" {
		return nil, errors.New("clientID is required")
	}
	statterWithClient := statter.WithTags(stats.Tags{"client": clientID})
	return &statterMiddleware{
		statter:  statterWithClient,
		delegate: delegate,
	}, nil
}

type statterMiddleware struct {
	statter  stats.Client
	delegate Client
}

const (
	unknownAction = "UNKNOWN"
)

// actionFromRequest parses the proto Request and extracts the action. This returns unknownAction
// if not action attribute was present in the request.
func actionFromRequest(req *proto.Request) (string, error) {
	action, present, err := req.Attribute("action")
	if err != nil {
		return "", err
	}
	if !present {
		return unknownAction, nil
	}
	asString, ok := action.(string)
	if !ok {
		return "", errors.New("unexpected action attribute type, should be string")
	}
	return asString, nil
}

// Authorize wraps the upstream Authorize method and reports timing information.
func (t *statterMiddleware) Authorize(ctx context.Context, request *proto.Request) (*proto.Decision, error) {
	start := time.Now()
	action, err := actionFromRequest(request)
	if err != nil {
		return nil, err
	}
	decision, err := t.delegate.Authorize(ctx, request)
	duration := time.Since(start)
	tags := stats.Tags{
		"batched": "false",
		"rpc":     "authorize",
		"action":  action,
	}
	if err != nil {
		tags["error_type"] = serverError
		t.statter.Counter(requestsMetric, tags, 1)
		t.statter.DistributionMs(timingMetric, tags, duration)
		return nil, err
	}

	tags["result"] = decision.GetResult().String()
	t.statter.Counter(requestsMetric, tags, 1)
	t.statter.DistributionMs(timingMetric, tags, duration)

	return decision, err
}

// BatchAuthorize wraps the upstream BatchAuthorize method and reports timing information.
func (t *statterMiddleware) BatchAuthorize(ctx context.Context, request *proto.BatchRequest) (*proto.BatchDecision, error) {
	start := time.Now()
	batchDecision, err := t.delegate.BatchAuthorize(ctx, request)
	duration := time.Since(start)

	tags := stats.Tags{
		"batched": "true",
		"rpc":     "batch_authorize",
	}

	if err != nil {
		tags["error_type"] = serverError
		t.statter.Counter(requestsMetric, tags, 1)
		t.statter.DistributionMs(timingMetric, tags, duration)
		return nil, err
	}

	t.statter.Counter(requestsMetric, tags, 1)
	t.statter.DistributionMs(timingMetric, tags, duration)

	start = time.Now()

	// each element in the batch will be reported as an individual metric. The latency will be the one of the batch as a whole. This allows for providing visibility for each individual `action` of the batch when they have different values.
	for idx, request := range request.GetRequests() {
		decision := batchDecision.GetDecisions()[idx]
		tags["action"], err = actionFromRequest(request)
		if err != nil {
			return nil, err
		}
		tags["result"] = decision.GetResult().String()
		t.statter.Counter(requestsMetric, tags, 1)
		t.statter.DistributionMs(timingMetric, tags, duration)
	}
	// issues a distribution for the time it took for the N+1 above, to make sure the overhead
	// aligns with the numbers seen in a benchmark conducted (1.3ms for 1000 elements)
	t.statter.DistributionMs(timingMetaMetric, nil, time.Since(start))

	return batchDecision, nil
}

func (t *statterMiddleware) ForActor(ctx context.Context, request *enumerator.ForActorRequest) (*enumerator.ForActorResponse, error) {
	start := time.Now()
	results, err := t.delegate.ForActor(ctx, request)
	duration := time.Since(start)
	tags := stats.Tags{
		"rpc": "for_actor",
	}

	if err != nil {
		tags["error_type"] = serverError
		t.statter.Counter(requestsMetric, tags, 1)
		t.statter.DistributionMs(timingMetric, tags, duration)
		return nil, err
	}

	t.statter.Counter(requestsMetric, tags, 1)
	t.statter.DistributionMs(timingMetric, tags, duration)

	return results, err
}

func (t *statterMiddleware) ForSubject(ctx context.Context, request *enumerator.ForSubjectRequest) (*enumerator.ForSubjectResponse, error) {
	start := time.Now()
	results, err := t.delegate.ForSubject(ctx, request)
	duration := time.Since(start)
	tags := stats.Tags{
		"rpc": "for_subject",
	}

	if err != nil {
		tags["error_type"] = serverError
		t.statter.Counter(requestsMetric, tags, 1)
		t.statter.DistributionMs(timingMetric, tags, duration)
		return nil, err
	}

	t.statter.Counter(requestsMetric, tags, 1)
	t.statter.DistributionMs(timingMetric, tags, duration)

	return results, err
}

func (t *statterMiddleware) EvaluatePoliciesForSingleResource(ctx context.Context, request *capevaluator.SingleResourceRequest) (*capevaluator.SingleResourceResponse, error) {
	start := time.Now()
	results, err := t.delegate.EvaluatePoliciesForSingleResource(ctx, request)
	duration := time.Since(start)
	tags := stats.Tags{
		"rpc": "evaluate_policies_for_single_resource",
	}

	if err != nil {
		tags["error_type"] = serverError
		t.statter.Counter(requestsMetric, tags, 1)
		t.statter.DistributionMs(timingMetric, tags, duration)
		return nil, err
	}

	t.statter.Counter(requestsMetric, tags, 1)
	t.statter.DistributionMs(timingMetric, tags, duration)

	return results, err
}
