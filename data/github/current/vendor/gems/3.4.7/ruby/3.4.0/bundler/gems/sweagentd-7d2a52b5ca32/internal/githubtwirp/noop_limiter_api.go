package githubtwirp

import (
	"context"

	copilotLimitersTwirp "github.com/github/copilot-twirp/proto/limiter/v1"
)

type NoopLimiterAPI struct {
	copilotLimitersTwirp.CopilotLimiterAPI
	MockGetQuotaRemaining  func(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error)
	MockGetConsumptiveUser func(ctx context.Context, req *copilotLimitersTwirp.GetConsumptiveUserRequest) (*copilotLimitersTwirp.GetConsumptiveUserResponse, error)
}

// Ensure NoopClient implements ClientInterface
var _ copilotLimitersTwirp.CopilotLimiterAPI = &NoopLimiterAPI{}

func (n *NoopLimiterAPI) GetQuotaRemaining(ctx context.Context, req *copilotLimitersTwirp.GetQuotaRemainingRequest) (*copilotLimitersTwirp.GetQuotaRemainingResponse, error) {
	if n.MockGetQuotaRemaining != nil {
		return n.MockGetQuotaRemaining(ctx, req)
	}

	return &copilotLimitersTwirp.GetQuotaRemainingResponse{
		QuotaDetails: []*copilotLimitersTwirp.QuotaDetails{
			{
				Entitlement:      1000,
				Remaining:        800,
				QuotaType:        copilotLimitersTwirp.QuotaType_QUOTA_TYPE_PREMIUM_INTERACTIONS,
				PercentRemaining: 0.8,
				OveragePermitted: true,
				QuotaRemaining:   10.0,
			},
		},
	}, nil
}

func (n *NoopLimiterAPI) GetConsumptiveUser(ctx context.Context, req *copilotLimitersTwirp.GetConsumptiveUserRequest) (*copilotLimitersTwirp.GetConsumptiveUserResponse, error) {
	if n.MockGetConsumptiveUser != nil {
		return n.MockGetConsumptiveUser(ctx, req)
	}

	return &copilotLimitersTwirp.GetConsumptiveUserResponse{
		CustomerIds: []int64{123},
	}, nil
}
