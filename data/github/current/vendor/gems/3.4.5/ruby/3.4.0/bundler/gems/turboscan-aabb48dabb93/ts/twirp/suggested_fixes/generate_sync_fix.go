package suggested_fixes

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/app"
	"github.com/github/turboscan/ts/appctx"
	"github.com/github/turboscan/ts/cocofix"
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

	appctx.Logger(ctx).Info("request received",
		kvp.String("gh.capi.interaction_id", req.InteractionId),
		kvp.String("gh.capi.interaction_type", req.InteractionType),
	)

	if len(req.Sarif) == 0 {
		return nil, twerrors.RequiredArgumentError("sarif")
	}

	var r *proto.GenerateSyncFixResponse

	res, err := s.sf.FixGenerator.GenerateDependabotFix(ctx, req.Sarif, []string{}, nil, 0, ts.CapiIntegrationCCR, ts.CapiInteraction{ID: req.InteractionId, Type: req.InteractionType})
	if err != nil {

		if cocofix.IsNonRetriableError(err) {
			r = &proto.GenerateSyncFixResponse{
				State: proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_ERROR,
				Error: proto.GenerateSyncFixError_GENERATE_SYNC_FIX_ERROR_NON_RETRIABLE,
			}

			payload := map[string]string{
				"integration": ts.CapiIntegrationCCR.String(),
			}
			appctx.Report(ctx, err, payload)
			err = nil
		} else if cocofix.IsTransientError(err) {
			r = &proto.GenerateSyncFixResponse{
				State: proto.SuggestedFixAlertState_SUGGESTED_FIX_ALERT_STATE_ERROR,
				Error: proto.GenerateSyncFixError_GENERATE_SYNC_FIX_ERROR_TRANSIENT,
			}
			err = nil
		}

		return r, err
	}

	r = &proto.GenerateSyncFixResponse{
		State: serializeSuggestedFixAlertState(res.SuggestedFixAlertState),
	}
	if res.SuggestedFix != nil {
		r.SuggestedFix = serializeSuggestedFix(res.SuggestedFix)
		r.AiModel = res.SuggestedFix.AiModel
		r.AiVersion = res.SuggestedFix.AiVersion
	}

	return r, nil
}
