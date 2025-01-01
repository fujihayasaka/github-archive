package transport

import (
	"context"
	"fmt"

	proto "github.com/github/attester/gen/go/attester/v0"
	"github.com/github/attester/pkg/auth"
	"github.com/github/attester/pkg/service"
	boo_service "github.com/github/attester/pkg/service/boo"
	"github.com/twitchtv/twirp"
)

/*
  GitHub API Service
*/

// NewBooService creates and configures a TwirpService that can be mounted
// on a router and dispatch calls for the Boo rpc interface.
// This service is used for creating and reading attestations from GitHub.com
func NewBooService(boo service.Service, cfg auth.HMACKeys, opts ...TwirpServiceOption) (*TwirpService, error) {
	service, err := newTwirpService(boo, opts...)
	if err != nil {
		return nil, fmt.Errorf("setting up twirp service: %w", err)
	}

	server := proto.NewBooAPIServer(service,
		service.hooks,
		twirp.WithServerInterceptors(service.interceptors),
		twirp.WithServerJSONCamelCaseNames(true))
	service.PathPrefix = server.PathPrefix()
	service.Handler = server

	// If authentication is enabled, create the auth middleware and wrap the
	// Twirp server in it. This middleware validates the HMAC of incoming requests
	authMiddleware, err := auth.NewAuthenticationMiddleware(service.log, cfg)
	if err != nil {
		return nil, fmt.Errorf("setting up HMAC auth: %w", err)
	}

	service.Handler = authMiddleware(server)

	return service, nil
}

func (ts *TwirpService) HelloName(ctx context.Context, req *proto.HelloNameRequest) (*proto.HelloNameResponse, error) {
	boo := ts.service.(boo_service.Service)

	return boo.HelloName(ctx, req)
}

func (ts *TwirpService) Error(ctx context.Context, req *proto.HelloNameRequest) (*proto.HelloNameResponse, error) {
	boo := ts.service.(boo_service.Service)
	return boo.Error(ctx, req)
}
