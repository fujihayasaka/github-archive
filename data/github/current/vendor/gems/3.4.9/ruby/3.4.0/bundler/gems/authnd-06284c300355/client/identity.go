package client

import (
	"context"
	"time"

	"github.com/github/authnd/client/middleware"
	pb "github.com/github/authnd/client/proto/authentication/v0"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
)

type IssueIdentityTokenRequest struct {
	Claims *pb.Claims
}

// NewIssueIdentityTokenRequest creates an IssueIdentityTokenRequest using the provided claim
func NewIssueIdentityTokenRequest(Claims *pb.Claims) *IssueIdentityTokenRequest {
	return &IssueIdentityTokenRequest{
		Claims: Claims,
	}
}

type IssueIdentityTokenResponse struct {
	Token string
}

type IdentityManager interface {
	IssueIdentityToken(ctx context.Context, request *IssueIdentityTokenRequest) (*IssueIdentityTokenResponse, error)
}

type identityManager struct {
	twirpClient pb.IdentityManager
	statter     stats.Client
}

func NewIdentityManager(addr, catalogService string, opts ...Option) (IdentityManager, error) {
	if addr == "" {
		return nil, errors.New("must provide a non empty addr")
	}
	if catalogService == "" {
		return nil, errors.New("must provide a non empty catalogService")
	}

	clientOpts := defaultClientOptions()
	err := applyOptions(clientOpts, opts...)
	if err != nil {
		return nil, errors.Wrap(err, "error applying options")
	}

	statter := clientOpts.Statter.WithTags(stats.Tags{
		catalogServiceDimensionName: catalogService,
		clientVersionDimensionName:  Version,
		serviceDimensionName:        "IdentityManagerIssueIdentityToken",
	})

	httpClient := clientOpts.CustomHTTPClient
	if httpClient == nil {
		httpClient = createHTTPClient(clientOpts.HTTPClientOptions, statter)
	}

	httpClient = middleware.ApplyCatalogService(httpClient, catalogService)
	httpClient = middleware.ApplyUserAgent(httpClient, Version)

	return &identityManager{
		pb.NewIdentityManagerProtobufClient(addr, httpClient),
		statter,
	}, nil
}

func (i *identityManager) IssueIdentityToken(ctx context.Context, request *IssueIdentityTokenRequest) (*IssueIdentityTokenResponse, error) {
	start := time.Now()
	tags := stats.Tags{methodDimensionName: "IssueIdentityToken"}
	defer func() {
		duration := time.Since(start)
		i.statter.Counter(requestsMetric, tags, 1)
		i.statter.DistributionMs(timingMetric, tags, duration)
	}()

	protobufRequest := &pb.IssueIdentityTokenRequest{
		Claims: request.Claims,
	}
	response, err := i.twirpClient.IssueIdentityToken(ctx, protobufRequest)
	if err != nil {
		tags["result"] = "twirp_client_error"
		return nil, err
	}

	return &IssueIdentityTokenResponse{
		Token: response.Token,
	}, nil
}
