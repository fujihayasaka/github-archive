package suggested_fixes

import (
	"context"

	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/o11y"
	"github.com/github/turboscan/ts/proto"
	"github.com/github/turboscan/ts/twirp/twerrors"
)

func init() {
	app.SpecialTimeoutHandler.Paths = append(app.SpecialTimeoutHandler.Paths, "/twirp/github.turboscan.SuggestedFixes/GenerateSyncFix")
}

func (s *Service) GenerateSyncFix(ctx context.Context, req *proto.GenerateSyncFixRequest) (*proto.GenerateSyncFixResponse, error) {
	ctx, span := o11y.StartSpan(ctx)
	defer span.End()

	appctx.Logger(ctx).Info("request received")

	if len(req.Sarif) == 0 {
		return nil, twerrors.RequiredArgumentError("sarif")
	}

	res, err := s.sf.FixGenerator.GenerateDependabotFix(ctx, req.Sarif, []string{}, nil, 0, s.sf.ProximaEnv)
	if err != nil {
		return nil, err
	}

	r := &proto.GenerateSyncFixResponse{
		State: serializeSuggestedFixAlertState(res.SuggestedFixAlertState),
	}
	if res.SuggestedFix != nil {
		r.SuggestedFix = serializeSuggestedFix(res.SuggestedFix)
		r.AiModel = res.SuggestedFix.AiModel
		r.AiVersion = res.SuggestedFix.AiVersion
	}

	return r, nil
}
