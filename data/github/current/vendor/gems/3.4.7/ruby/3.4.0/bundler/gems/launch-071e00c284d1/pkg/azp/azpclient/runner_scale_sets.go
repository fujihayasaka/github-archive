package azpclient

import (
	"context"
	"net/http"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

type RunnerScaleSetsService struct {
	client *Client
	http   *httpclient.Client
}

func (s *RunnerScaleSetsService) GetRunnerScaleSet(ctx context.Context, scaleSetID int64) (*azp.RunnerScaleSet, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnerscaleset.get"
	var resp *azp.RunnerScaleSet

	err := s.http.Do(
		ctx,
		opname,
		http.MethodGet,
		s.client.url.getRunnerScaleSetURL(scaleSetID),
		nil,
		&resp,
		s.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}

func (s *RunnerScaleSetsService) ListRunnerScaleSets(ctx context.Context, excludeElasticRunners bool) ([]*azp.RunnerScaleSet, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "runnerscaleset.list"
	var resp runnerScaleSetsListResponse

	err := s.http.Do(
		ctx,
		opname,
		http.MethodGet,
		s.client.url.getRunnerScaleSetsURL(excludeElasticRunners),
		nil,
		&resp,
		s.client.withDefaultOpts(ctx)...,
	)
	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp.Value, nil
}

type runnerScaleSetsListResponse struct {
	Count int64                 `json:"count"`
	Value []*azp.RunnerScaleSet `json:"value"`
}
