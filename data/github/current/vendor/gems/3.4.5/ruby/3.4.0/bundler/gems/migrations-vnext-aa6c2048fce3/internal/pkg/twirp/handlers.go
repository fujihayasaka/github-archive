package twirp

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	v1 "github.com/github/migrations-vnext/pkg/mvnd/v1"
	"github.com/twitchtv/twirp"
)

// AbortMigration is the entrypoint for the AbortMigration RPC that aborts a migration.
func (s *Server) AbortMigration(_ context.Context, _ *v1.AbortMigrationRequest) (*v1.AbortMigrationResponse, error) {
	// TODO implement me
	return nil, twirp.NewError(twirp.Unimplemented, "endpoint not implemented yet")
}

// CreateResource is the entrypoint for the CreateResource RPC that creates (loads) a resource.
func (s *Server) CreateResource(ctx context.Context, req *v1.CreateResourceRequest) (*v1.CreateResourceResponse, error) {
	s.logger.WithFields(
		kvp.Int64("migration_id", req.GetMigrationId()),
		kvp.String("resource_type", resourceToTypeName(req.GetResource())),
	).Info("CreateResource")

	if err := s.manager.AddResource(ctx, req.GetResource()); err != nil {
		s.logger.WithError(err).Error("failed to enqueue resource creation", kvp.Any("resource", req.GetResource()))
		return nil, twirp.InternalError("failed to enqueue resource creation")
	}

	return &v1.CreateResourceResponse{}, nil
}

// MigrationStatus is the entrypoint for the MigrationStatus RPC that returns the status of a migration.
func (s *Server) MigrationStatus(ctx context.Context, req *v1.MigrationStatusRequest) (*v1.MigrationStatusResponse, error) {
	// TODO implement me
	return nil, twirp.NewError(twirp.Unimplemented, "endpoint not implemented yet")
}

// PauseMigrations is the entrypoint for the PauseMigrations RPC that pauses a migration.
func (s *Server) PauseMigrations(_ context.Context, _ *v1.PauseMigrationsRequest) (*v1.PauseMigrationsResponse, error) {
	// TODO implement me
	return nil, twirp.NewError(twirp.Unimplemented, "endpoint not implemented yet")
}

// ResumeMigrations is the entrypoint for the ResumeMigrations RPC that resumes a migration.
func (s *Server) ResumeMigrations(_ context.Context, _ *v1.ResumeMigrationsRequest) (*v1.ResumeMigrationsResponse, error) {
	// TODO implement me
	return nil, twirp.NewError(twirp.Unimplemented, "endpoint not implemented yet")
}

// StoreEvent is the entrypoint for the StoreEvent RPC that stores an event in the
// event store.
func (s *Server) StoreEvent(ctx context.Context, req *v1.StoreEventRequest) (*v1.StoreEventResponse, error) {
	s.logger.WithFields(
		kvp.Int64("migration_id", req.GetMigrationId()),
		kvp.Any("event_id", req.GetEvent().EventId),
		kvp.Any("event_action", req.GetEvent().EventAction),
	).Info("StoreEvent")

	// Perform top-level validation
	if err := validateEvent(req.GetEvent()); err != nil {
		return &v1.StoreEventResponse{}, twirp.NewError(twirp.InvalidArgument, err.Error())
	}

	if err := s.manager.AddEvent(ctx, req.GetEvent()); err != nil {
		s.logger.WithError(err).Error("failed to store event")
		return nil, twirp.InternalError("failed to store event")
	}

	return &v1.StoreEventResponse{}, nil
}

// validateEvent is a helper function which checks that the composition
// of an event is valid. If it is not, an error will be returned stating
// what was wrong.
func validateEvent(e *v1.Event) error {
	if e == nil {
		return fmt.Errorf("%w: event is empty", ErrMalformedEvent)
	}

	if e.EventAction == 0 {
		return fmt.Errorf("%w: event action must not be 0 (unknown)", ErrMalformedEvent)
	}

	if e.EventId == "" {
		return fmt.Errorf("%w: event_id field not present", ErrMalformedEvent)
	}

	if e.ResourceId == "" {
		return fmt.Errorf("%w: resource_id field not present", ErrMalformedEvent)
	}

	if e.Timestamp == nil {
		return fmt.Errorf("%w: timestamp field not present", ErrMalformedEvent)
	}

	return nil
}

// GenerateSignedUploadURL is the entrypoint that returns a signed URL for an upload request.
func (s *Server) GenerateSignedUploadURL(ctx context.Context, req *v1.GenerateSignedUploadURLRequest) (*v1.GenerateSignedUploadURLResponse, error) {
	signedURL, err := s.sasGenerator.GenerateSignedURL(req.AssetKind, req.FileName, req.ContentType, req.FileSizeBytes)
	if err != nil {
		return nil, fmt.Errorf("unable to generate signed upload url: %w", err)
	}

	return &v1.GenerateSignedUploadURLResponse{
		SignedUrl: signedURL.String(),
	}, nil
}

func resourceToTypeName(r *v1.Resource) string {
	switch r.GetResource().(type) {
	case *v1.Resource_Issue:
		return "issue"
	case *v1.Resource_IssueComment:
		return "issue comment"
	case *v1.Resource_Mannequin:
		return "mannequin"
	case *v1.Resource_Organization:
		return "organization"
	case *v1.Resource_Repository:
		return "repository"
	case *v1.Resource_PullRequest:
		return "pull request"
	case *v1.Resource_PullRequestReview:
		return "pull request review"
	case *v1.Resource_ReactionsBatch:
		return "reactions batch"
	default:
		return "unknown"
	}
}
