package app

import (
	"context"
	"net/http"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-twirp/v2/server/hooks/log"
	"github.com/github/otel-instrumentation-go/oteltwirp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/proto"
	"github.com/twitchtv/twirp"
)

type requestWithRepositoryID interface {
	GetRepositoryId() uint64
}

type requestWithRepositoryIDs interface {
	GetRepositoryIds() []uint64
}

type requestWithOwnerIDs interface {
	GetOwnerIds() []uint64
}

// check any one of the requests with GetRepositoryId matches to verify the signature is correct
var _ requestWithRepositoryID = &proto.CreateDeliveryRequest{}

// check any one of the requests with GetRepositoryIds matches to verify the signature is correct
var _ requestWithRepositoryIDs = &proto.AlertsByRepoRequest{}

// check any one of the requests with GetOwnerIds matches to verify the signature is correct
var _ requestWithOwnerIDs = &proto.AlertsByRepoRequest{}

func Handler(r proto.Results, i proto.Insights, ma proto.ManagedAnalyses, sf proto.SuggestedFixes, opts ...interface{}) http.Handler {
	opts = append(opts, twirp.WithServerInterceptors(func(m twirp.Method) twirp.Method {
		return func(ctx context.Context, request interface{}) (interface{}, error) {
			fields := log.DefaultFields(ctx)
			if req, ok := request.(requestWithRepositoryID); ok {
				fields = append(fields, ts.RepositoryEID(req.GetRepositoryId()).AsKVP())
			}
			if req, ok := request.(requestWithRepositoryIDs); ok {
				repoIDs := req.GetRepositoryIds()
				fields = append(fields, kvp.Uint64s("gh.repo.ids", repoIDs))
				// If there is just a single repo we also add it to the other parameter
				if len(repoIDs) == 1 {
					fields = append(fields, ts.RepositoryEID(repoIDs[0]).AsKVP())
				}
			}
			if req, ok := request.(requestWithOwnerIDs); ok {
				fields = append(fields, kvp.Uint64s("gh.turboscan.owner_ids", req.GetOwnerIds()))
			}

			return m(appctx.With(ctx, fields...), request)
		}
	}))

	resultsSvc := proto.NewResultsServer(r, opts...)
	insightsSvc := proto.NewInsightsServer(i, opts...)
	managedAnalysesSvc := proto.NewManagedAnalysesServer(ma, opts...)
	suggestedFixesSvc := proto.NewSuggestedFixesServer(sf, opts...)

	twirpMux := http.NewServeMux()
	twirpMux.Handle(resultsSvc.PathPrefix(), resultsSvc)
	twirpMux.Handle(insightsSvc.PathPrefix(), insightsSvc)
	twirpMux.Handle(managedAnalysesSvc.PathPrefix(), managedAnalysesSvc)
	twirpMux.Handle(suggestedFixesSvc.PathPrefix(), suggestedFixesSvc)

	return oteltwirp.Middleware(twirpMux)
}
