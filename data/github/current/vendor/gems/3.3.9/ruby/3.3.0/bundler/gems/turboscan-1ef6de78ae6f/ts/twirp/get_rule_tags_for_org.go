package twirp

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/tstypes"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (r *ResultsResolver) GetRuleTagsForOrg(ctx context.Context, req *proto.RuleTagsForOrgRequest) (*proto.RuleTagsForOrgResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.repo.ids.excluded", fmt.Sprint(req.ExcludedRepositoryIds)),
	)

	if len(req.OwnerIds) == 0 {
		return nil, o11y.RecordError(span, twerrors.RequiredArgumentError("owner_ids"))
	}

	filter, err := tstypes.CreateSearchByOrgsFilter(req.OwnerIds, req.RepositoryIds, req.ExcludedRepositoryIds, req.Filter)
	if err != nil {
		return nil, o11y.RecordError(span, err)
	}

	ruleTags, err := r.es.SearchOrgRuleTags(ctx, filter)
	if err != nil {
		return nil, o11y.RecordError(span, twerrors.InternalErrorWith(err))
	}

	return &proto.RuleTagsForOrgResponse{
		RuleTags: ruleTags,
	}, nil
}
