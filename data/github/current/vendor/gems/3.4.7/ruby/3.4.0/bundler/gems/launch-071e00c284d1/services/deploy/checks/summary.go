package checks

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/launch/observability"
	"github.com/github/launch/observability/tracing"
	svcerr "github.com/github/launch/services/errors"
	"github.com/github/launch/types"
)

func (s *service) GetSummaryExchangeURL(ctx context.Context, req *SummaryExchangeURLRequest) (*SummaryExchangeURLResponse, error) {
	ctx, span := tracing.Start(ctx)
	defer span.End()

	obs := observability.New(s.log, s.stats)
	s.startLatencyCheckpoint(obs)
	defer s.logLatencyCheckpoint(ctx, obs, "getsummaryexchangeurl")

	oid := types.NewGlobalID(ctx, req.GetRepositoryId().GetGlobalId())
	if oid.IsZeroValue() {
		return nil, svcerr.NewInvalidArgumentError("repo id cannot be nil")
	}

	// Check if blank string provided
	if len(req.UnauthenticatedJobSummariesUrl) == 0 {
		return nil, svcerr.NewInvalidArgumentError("request url is blank")
	}

	// Get Azure Repo client
	arClient, err := s.getAzureRepositoryClient(ctx, oid)
	if err != nil {
		obs.Report(ctx, errors.Wrap(err, "unable to get azure repository client"), kvp.String("gh.launch.oid", oid.String()))
		return nil, svcerr.NewInternalError(err.Error())
	}

	url, err := arClient.GetAuthenticatedURL(ctx, req.UnauthenticatedJobSummariesUrl)
	if err != nil {
		obs.Report(ctx, errors.Wrap(err, "unable to get back signed url for summary"), kvp.String("gh.launch.oid", oid.String()))
		return nil, svcerr.NewInternalError(err.Error())
	}

	return &SummaryExchangeURLResponse{
		AuthenticatedUrl: url.SignedContent.URL,
		ExpiresAt:        timestamppb.New(url.SignedContent.SignatureExpires),
	}, nil
}
