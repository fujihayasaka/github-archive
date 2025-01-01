package transport

import (
	"context"
	"fmt"

	proto "github.com/github/attester/gen/go/attester/v0"
	"github.com/github/attester/pkg/auth"
	"github.com/github/attester/pkg/service"
	release_service "github.com/github/attester/pkg/service/release"
	"github.com/twitchtv/twirp"
)

/*
  GitHub API Service
*/

func NewReleaseService(release service.Service, cfg auth.HMACKeys, opts ...TwirpServiceOption) (*TwirpService, error) {
	service, err := newTwirpService(release, opts...)
	if err != nil {
		return nil, fmt.Errorf("setting up twirp service: %w", err)
	}

	server := proto.NewReleaseAPIServer(service,
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

func (ts *TwirpService) CreateReleaseAttestation(ctx context.Context, req *proto.CreateReleaseAttestationRequest) (*proto.CreateReleaseAttestationResponse, error) {
	ts.log.Info("CreateReleaseAttestation")

	release := ts.service.(release_service.Service)

	return release.CreateReleaseAttestation(ctx, req)
}
