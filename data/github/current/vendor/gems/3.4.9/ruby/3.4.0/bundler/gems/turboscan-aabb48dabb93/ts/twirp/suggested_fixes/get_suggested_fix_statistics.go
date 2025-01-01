package suggested_fixes

import (
	"context"

	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/mysql/suggestedfixes"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func (s *Service) GetSuggestedFixStatistics(ctx context.Context, req *proto.GetSuggestedFixStatisticsRequest) (*proto.GetSuggestedFixStatisticsResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received")

	if len(req.OwnerIds) == 0 {
		return nil, o11y.RecordError(span, twerrors.RequiredArgumentError("owner_ids"))
	}

	if req.Start == nil {
		return nil, o11y.RecordError(span, twerrors.RequiredArgumentError("start"))
	}

	if req.End == nil {
		return nil, o11y.RecordError(span, twerrors.RequiredArgumentError("end"))
	}

	filter := suggestedfixes.StatisticsFilter{
		OwnerIds:       req.OwnerIds,
		RepositoryIds:  req.RepositoryIds,
		RuleIds:        req.RuleIds,
		ExcludeRuleIds: req.ExcludeRuleIds,
		Severities:     req.Severities,
		Start:          req.Start.AsTime(),
		End:            req.End.AsTime(),
	}
	res, err := s.sf.DbService.GetSuggestedFixStatistics(ctx, filter)
	if err != nil {
		return nil, err
	}

	return &proto.GetSuggestedFixStatisticsResponse{
		Suggested: res.TotalSuggested,
	}, nil
}
