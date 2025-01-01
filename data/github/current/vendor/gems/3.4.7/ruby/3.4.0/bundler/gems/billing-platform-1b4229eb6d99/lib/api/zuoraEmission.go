package api

import (
	"context"

	"github.com/github/billing-platform/lib/engines"
	"github.com/github/billing-platform/lib/models"
	"github.com/github/billing-platform/lib/twirp/proto"
	"github.com/github/github-telemetry-go/log"
	"github.com/twitchtv/twirp"
)

type ZuoraEmissionAPI struct {
	zuoraEngine engines.ZuoraEngineInterface
	logger      log.Logger
}

func NewZuoraEmissionAPI(zuoraEngine engines.ZuoraEngineInterface, logger log.Logger) *ZuoraEmissionAPI {
	return &ZuoraEmissionAPI{
		zuoraEngine: zuoraEngine,
		logger:      logger,
	}
}
func (api *ZuoraEmissionAPI) GetZuoraEmissions(ctx context.Context, req *proto.GetZuoraEmissionsRequest) (*proto.GetZuoraEmissionsResponse, error) {
	if req.CustomerId == "" {
		return nil, twirp.RequiredArgumentError("customer_id")
	}

	emissions, err := api.zuoraEngine.GetZuoraEmissions(ctx, api.logger, req.CustomerId, req.Year, req.Month, req.Day)
	if err != nil {
		return nil, twirp.InternalErrorWith(err)
	}

	protoEmissions := make([]*proto.ZuoraEmission, len(emissions))
	for i, emission := range emissions {
		partitionDetail := &models.EmissionPartitionDetail{
			CustomerId: req.CustomerId,
			Year:       req.Year,
			Month:      req.Month,
			Day:        req.Day,
		}
		protoEmissions[i] = emission.ToProto(partitionDetail)
	}

	return &proto.GetZuoraEmissionsResponse{
		Emissions: protoEmissions,
	}, nil
}
