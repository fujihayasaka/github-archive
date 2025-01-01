package selfhostedrunners

import (
	context "context"

	"github.com/github/go-kvp"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/ghtenant"
)

// RegisterRunner is used to register a runner with AZP
func (s *service) RegisterRunner(ctx context.Context, req *RegisterRunnerRequest) (*RegisterRunnerResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()
	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "registerrunner")

	oid := s.getOwnerIDFromRegisterRequest(ctx, req)
	if oid.IsZeroValue() {
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("owner id cannot be nil"))
	}

	ctx = ctxstash.WithFields(ctx, kvp.String("gh.owner.global_id", oid.String()))

	tenantSlug, err := ghtenant.TenantSlugFromContext(ctx, s.isMultiTenant)
	if err != nil {
		return nil, tracing.RecordError(span, svcerr.NewInvalidArgumentError("tenant slug cannot be nil for proxima"))
	}

	arc, err := s.getAzureRepositoryClient(ctx, oid)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInvalidArgumentError(err.Error())
	}

	rrc, err := arc.GetRunnerRegistrationCredentials(ctx, s.getOwnerIDFromRegisterRequest(ctx, req), s.getBillingOwnerIDFromRegisterRequest(ctx, req), tenantSlug)
	if err != nil {
		obs.Report(ctx, err)
		return nil, svcerr.NewInternalError(err.Error())
	}

	if rrc.HostURL != "" {
		return &RegisterRunnerResponse{
			Url:         rrc.HostURL,
			Token:       rrc.Data.Token,
			TokenSchema: rrc.Scheme,
		}, nil
	}
	return &RegisterRunnerResponse{
		Url:         rrc.Data.HostURL,
		Token:       rrc.Data.Token,
		TokenSchema: rrc.Scheme,
	}, nil
}

func (s *service) getOwnerIDFromRegisterRequest(ctx context.Context, req *RegisterRunnerRequest) types.GlobalID {
	return types.NewGlobalID(ctx, req.GetOwnerId().GetGlobalId())
}

func (s *service) getBillingOwnerIDFromRegisterRequest(ctx context.Context, req *RegisterRunnerRequest) types.GlobalID {
	return types.NewGlobalID(ctx, req.GetBillingOwnerId().GetGlobalId())
}
