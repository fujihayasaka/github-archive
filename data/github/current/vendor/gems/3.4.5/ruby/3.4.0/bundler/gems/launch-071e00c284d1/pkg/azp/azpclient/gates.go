package azpclient

import (
	"context"
	"fmt"
	"net/http"
	"strings"

	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/azp"
	"github.com/github/launch/pkg/launchhttp"
	"github.com/github/launch/pkg/launchhttp/httpclient"
)

type GatesService struct {
	client         *Client
	http           *httpclient.Client
	useDefaultAuth func(ctx context.Context) bool
}

func (g *GatesService) UpdateGateConclusion(ctx context.Context, gateID string, planID string, jobExternalID string, token string, isOpen bool) error {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	opname := "gates.update"

	if strings.TrimSpace(gateID) == "" {
		return fmt.Errorf("the gate id cannot be empty")
	}

	body := azp.GateConclusion{
		PlanID:        planID,
		JobKey:        "", // not used for now
		JobExternalID: jobExternalID,
		IsOpen:        isOpen,
		State:         "", // not used for now
	}

	var doOpts []httpclient.DoOption

	if g.useDefaultAuth(ctx) {
		// Use the default client authentication and ignore the provided token
		doOpts = g.client.withDefaultOpts(ctx,
			httpclient.WithRequestOptions(
				launchhttp.WithJSONContentType(),
			),
			httpclient.WithValidator(azp.ResponseValidator()),
		)
	} else {
		// N.b. this call uses a token provided via argument to authenticate so we need to remove the default, client wide, authentication
		// options and other defaults, and overwrite them.
		doOpts = []httpclient.DoOption{
			httpclient.WithRequestOptions(
				launchhttp.WithBearerToken(token),
				launchhttp.WithADNCorrelationHeaders(ctx),
				launchhttp.WithJSONContentType(),
			),
			httpclient.WithRetries(azp.ResponseValidator()),
			httpclient.WithValidator(azp.ResponseValidator()),
		}
	}

	if g.client.options.breaker != nil {
		doOpts = append(doOpts, httpclient.WithBreaker(g.client.options.breaker))
	}

	err := g.http.Do(
		ctx,
		opname,
		http.MethodPatch,
		g.client.url.getUpdateGateURL(gateID),
		body,
		nil,
		doOpts...,
	)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	return nil
}
