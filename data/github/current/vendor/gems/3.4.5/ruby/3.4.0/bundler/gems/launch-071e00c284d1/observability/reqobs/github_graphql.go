package reqobs

import (
	"context"
	"strconv"

	"github.com/github/launch/clients/github"
	"github.com/github/launch/observability"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/pkg/launchhttp"
)

func GitHubGraphQLHooks(obs *observability.Observability) *github.ClientHooks {
	return &github.ClientHooks{
		OnBeginRPC: func(ctx context.Context, opname, optype string) {
			tags := buildOnBeginRPCTags("graphql."+optype, "github", "github", opname)
			emitOnAttemptCounter(ctx, obs.Statter, tags)
		},
		OnStartPerformRequest: func(ctx context.Context, opname, optype string, attempt int) {},
		OnDonePerformRequest: func(ctx context.Context, opname, optype string, res *github.ReqResult) {
			if res.Err != nil {
				tags := graphqlTagsFor(opname, optype, 0, 0, launchhttp.GetLowCardinalityErrorCategory(res.Err))
				emitOnDonePerformRequest(ctx, obs.Statter, res.Duration, res.Err, tags)
			}
		},
		OnStartHandleResponse: func(ctx context.Context, opname, optype string) {

		},
		OnDoneHandleResponse: func(ctx context.Context, opname, optype string, res *github.RespResult) {
			if res.Err != nil {
				obs.ErrorWithFields(ctx, "github graphql error", res.Err)
			}

			tags := graphqlTagsFor(opname, optype, res.Attempt, res.Code, res.Status)
			emitOnDoneHandleResponse(ctx, obs.Statter, res.Duration, tags)
		},
		OnEndRPC: func(ctx context.Context, opname, optype string, res *github.RPCResult) {
			tags := graphqlTagsFor(opname, optype, res.Attempt, res.Code, res.Status)
			emitOnEndRPC(ctx, obs.Statter, res.Duration, tags, res.Status == github.ErrorStatusValue)
		},
	}
}

func graphqlTagsFor(opname, optype string, attempt, statusCode int, errorStatus string) statter.Tags {
	tags := buildOnBeginRPCTags("graphql."+optype, "github", "github", opname)

	if attempt > 0 {
		tags["attempt"] = strconv.Itoa(attempt)
	}

	if statusCode > 0 {
		tags[AttemptStatusCodeMetricTag] = strconv.Itoa(statusCode)
	}

	if errorStatus != "" {
		tags[AttemptErrorCodeMetricTag] = errorStatus
		tags[AttemptErrorMetricTag] = "true"
	} else {
		tags[AttemptErrorMetricTag] = "false"
	}

	return tags
}
