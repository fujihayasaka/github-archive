package azpclient

import (
	"context"
	"net/http"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

type URLExchangeService struct {
	client *Client
	http   *httpclient.Client
}

func (u *URLExchangeService) GetAuthenticatedURL(ctx context.Context, url string) (*azp.GetAuthenticatedURLResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "urlexchange"

	var resp *azp.GetAuthenticatedURLResponse
	err := u.http.Do(
		ctx,
		opname,
		http.MethodGet,
		url,
		nil,
		&resp,
		u.client.withDefaultOpts(ctx)...,
	)

	if err != nil {
		return nil, tracing.RecordError(span, err)
	}

	return resp, nil
}
