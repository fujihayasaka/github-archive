package diagnostic

import (
	"context"

	"github.com/pkg/errors"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/pkg/proto"
	"github.com/twitchtv/twirp"
)

// service holds the methods for our service implementation as well as a few dependencies.
type service struct {
	diagnosticSvc interfaces.DiagnosticService
}

// CreateTwirpServer creates a new TwirpServer instance that adheres to DiagnosticService's API.
func CreateTwirpServer(hooks *twirp.ServerHooks, diagnosticSvc interfaces.DiagnosticService) proto.TwirpServer {
	service := CreateService(diagnosticSvc)
	return proto.NewDiagnosticServiceServer(service, hooks)
}

// CreateService creates a new proto.DiagnosticService.
func CreateService(diagnosticSvc interfaces.DiagnosticService) proto.DiagnosticService {
	service := &service{
		diagnosticSvc: diagnosticSvc,
	}

	return service
}

func (s *service) Ping(ctx context.Context, req *proto.PingRequest) (*proto.PingResponse, error) {
	message := s.diagnosticSvc.Ping()
	return &proto.PingResponse{Message: message}, nil
}

func (s *service) Boom(ctx context.Context, req *proto.BoomRequest) (*proto.BoomResponse, error) {
	_, err := s.diagnosticSvc.Boom(req.ShouldPanic)
	return &proto.BoomResponse{}, err
}

func (s *service) Timeout(ctx context.Context, req *proto.TimeoutRequest) (*proto.TimeoutResponse, error) {
	s.diagnosticSvc.Timeout(req.SleepDurationSeconds)
	return &proto.TimeoutResponse{}, nil
}

func (s *service) IsFeatureFlagEnabled(ctx context.Context, req *proto.IsFeatureFlagEnabledRequest) (*proto.IsFeatureFlagEnabledBatchResponse, error) {
	if req.GetActors() == nil {
		isEnabled, err := s.diagnosticSvc.IsFeatureFlagEnabled(ctx, req.Feature)
		if err != nil {
			return nil, twirp.WrapError(
				twirp.NewError(twirp.Internal, "querying IsFeatureFlagEnabled globally"),
				errors.Wrapf(err, "in IsFeatureFlagEnabled"))
		}
		return &proto.IsFeatureFlagEnabledBatchResponse{IsEnabled: isEnabled}, nil
	}
	isEnabled, err := s.diagnosticSvc.IsFeatureFlagEnabled(ctx, req.Feature, req.Actors...)
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "querying IsFeatureFlagEnabled"),
			errors.Wrapf(err, "in IsFeatureFlagEnabled"))
	}
	return &proto.IsFeatureFlagEnabledBatchResponse{IsEnabled: isEnabled}, nil
}

func (s *service) IsFeatureFlagEnabledForRepository(ctx context.Context, req *proto.IsFeatureFlagEnabledForRepositoryRequest) (*proto.IsFeatureFlagEnabledSingleResponse, error) {
	isEnabled, err := s.diagnosticSvc.IsFeatureFlagEnabledForRepository(ctx, req.Feature, req.RepositoryId)
	if err != nil {
		return nil, twirp.WrapError(
			twirp.NewError(twirp.Internal, "querying IsFeatureFlagEnabledForRepository"),
			errors.Wrapf(err, "in IsFeatureFlagEnabledForRepository"))
	}
	return &proto.IsFeatureFlagEnabledSingleResponse{IsEnabled: isEnabled}, nil
}
