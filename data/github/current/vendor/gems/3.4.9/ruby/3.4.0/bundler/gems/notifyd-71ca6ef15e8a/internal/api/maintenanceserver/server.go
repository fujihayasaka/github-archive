// Package maintenanceserver provise the Twirp API for maintenance operations within notifyd.
package maintenanceserver

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	"github.com/twitchtv/twirp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/emptypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	"github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	hydropb "github.com/github/notifyd/hydro/schemas/notifyd/v1"
	"github.com/github/notifyd/internal/api"
	metricspkg "github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/o11y"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/tenancy"
	apipb "github.com/github/notifyd/proto/services/maintenance"
)

const (
	deleteRepositoryTopic         = "notifyd.v1.DeleteRepository"
	deleteRepositoryForUsersTopic = "notifyd.v1.DeleteRepositoryForUsers"
	deleteUserTopic               = "notifyd.v1.DeleteUser"
	deleteUserRepositoriesTopic   = "notifyd.v1.DeleteUserRepositories"
)

// Publisher is an interface for publishing messages to hydro.
type Publisher interface {
	Publish(m proto.Message, opts ...hydro.PublishOption) error
}

// Server represents a maintenance server.
type Server struct {
	publisher Publisher
	telem     *telemetry.Provider
	metrics   *metricspkg.PublisherMetrics
}

// NewServer creates a new maintenance server.
func NewServer(publisher Publisher, telem *telemetry.Provider, metrics *metricspkg.PublisherMetrics) Server {
	return Server{
		publisher: publisher,
		telem:     telem,
		metrics:   metrics,
	}
}

// Handler returns a handler for the maintenance server.
func (s Server) Handler(hooks *twirp.ServerHooks) api.Handler {
	return apipb.NewMaintenanceServer(s, hooks)
}

// DeleteRepository publishes a message to delete a repository.
func (s Server) DeleteRepository(ctx context.Context, req *apipb.DeleteRepositoryRequest) (*emptypb.Empty, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "maintenanceserver")
	ctx = o11y.CtxSetMethod(ctx, "deleterepository")

	repositoryID := req.GetRepositoryId()
	logger := s.telem.Logger.WithContext(ctx).WithFields(kvp.Int64("gh.repo.id", repositoryID))

	if repositoryID <= 0 {
		err := fmt.Errorf("invalid repository ID %d", repositoryID)
		logger.WithError(err).Error("Invalid request")
		return nil, err
	}

	tenant, err := tenancy.FromContext(ctx)
	if err != nil {
		logger.Error("Unable to extract tenant information from request context")
		return nil, err
	}

	msg := &hydropb.DeleteRepository{
		RepositoryId: repositoryID,
		Retries:      &entities.Retries{Attempts: 0},
		Tracking:     &entities.Tracking{TriggeredAt: timestamppb.Now()},
	}

	headers := make(map[string]string)
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(headers))
	tenancy.Inject(tenant, headers)

	err = s.publisher.Publish(msg, hydro.WithTopic(deleteRepositoryTopic), hydro.WithCustomHeaders(headers))
	s.metrics.Send(ctx, "delete_repository", err, metricspkg.WithHydroKey())
	if err != nil {
		logger.Error("Unable to publish the message")
		return nil, err
	}

	return &emptypb.Empty{}, nil
}

// DeleteRepositoryForUsers publishes a message to delete a repository for a list of users.
func (s Server) DeleteRepositoryForUsers(ctx context.Context, req *apipb.DeleteRepositoryForUsersRequest) (*emptypb.Empty, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "maintenanceserver")
	ctx = o11y.CtxSetMethod(ctx, "deleterepositoryforusers")

	repositoryID := req.GetRepositoryId()
	userIDs := req.GetUserIds()

	logger := s.telem.Logger.WithContext(ctx).WithFields(kvp.Int64("gh.repo.id", repositoryID), kvp.Int64s("gh.notifyd.user.ids", userIDs))

	if repositoryID <= 0 {
		err := fmt.Errorf("invalid repository ID %d", repositoryID)
		logger.WithError(err).Error("Invalid request")
		return nil, err
	}

	if len(userIDs) == 0 {
		err := fmt.Errorf("no user IDs provided for repositoryID: %v", repositoryID)
		logger.WithError(err).Error("Invalid request")
		return nil, err
	}

	tenant, err := tenancy.FromContext(ctx)
	if err != nil {
		logger.Error("Unable to extract tenant information from request context")
		return nil, err
	}

	msg := &hydropb.DeleteRepositoryForUsers{
		RepositoryId: repositoryID,
		UserIds:      userIDs,
		Retries:      &entities.Retries{Attempts: 0},
		Tracking:     &entities.Tracking{TriggeredAt: timestamppb.Now()},
	}

	headers := make(map[string]string)
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(headers))
	tenancy.Inject(tenant, headers)

	err = s.publisher.Publish(msg, hydro.WithTopic(deleteRepositoryForUsersTopic), hydro.WithCustomHeaders(headers))
	s.metrics.Send(ctx, "delete_repository_for_users", err, metricspkg.WithHydroKey())
	if err != nil {
		logger.Error("Unable to publish the message")
		return nil, err
	}

	return &emptypb.Empty{}, nil
}

// DeleteUser publishes a message to delete a user.
func (s Server) DeleteUser(ctx context.Context, req *apipb.DeleteUserRequest) (*emptypb.Empty, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "maintenanceserver")
	ctx = o11y.CtxSetMethod(ctx, "deleteuser")

	userID := req.GetUserId()

	logger := s.telem.Logger.WithContext(ctx).WithFields(kvp.Int64("gh.user.id", userID))

	if userID <= 0 {
		err := fmt.Errorf("invalid user ID: %d", userID)
		logger.WithError(err).Error("Invalid request")
		return nil, err
	}

	tenant, err := tenancy.FromContext(ctx)
	if err != nil {
		logger.Error("Unable to extract tenant information from request context")
		return nil, err
	}

	msg := &hydropb.DeleteUser{
		UserId:   userID,
		Retries:  &entities.Retries{Attempts: 0},
		Tracking: &entities.Tracking{TriggeredAt: timestamppb.Now()},
	}

	headers := make(map[string]string)
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(headers))
	tenancy.Inject(tenant, headers)

	err = s.publisher.Publish(msg, hydro.WithTopic(deleteUserTopic), hydro.WithCustomHeaders(headers))
	s.metrics.Send(ctx, "delete_user", err, metricspkg.WithHydroKey())
	if err != nil {
		logger.Error("Unable to publish the message")
		return nil, err
	}

	return &emptypb.Empty{}, nil
}

// DeleteUserRepositories publishes a message to delete a user's repositories.
func (s Server) DeleteUserRepositories(ctx context.Context, req *apipb.DeleteUserRepositoriesRequest) (*emptypb.Empty, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	ctx = o11y.CtxSetPackage(ctx, "maintenanceserver")
	ctx = o11y.CtxSetMethod(ctx, "deleteuserrepositories")

	userID := req.GetUserId()
	repositoryIDs := req.GetRepositoryIds()

	logger := s.telem.Logger.WithContext(ctx).WithFields(kvp.Int64("gh.user.id", userID), kvp.Int64s("gh.notifyd.repo.ids", repositoryIDs))

	if userID <= 0 {
		err := fmt.Errorf("invalid user ID: %v", userID)
		logger.WithError(err).Error("Invalid request")
		return nil, err
	}

	if len(repositoryIDs) == 0 {
		err := fmt.Errorf("no repository IDs provided for userID: %v", userID)
		logger.WithError(err).Error("Invalid request")
		return nil, err
	}

	tenant, err := tenancy.FromContext(ctx)
	if err != nil {
		logger.Error("Unable to extract tenant information from request context")
		return nil, err
	}

	msg := &hydropb.DeleteUserRepositories{
		UserId:        userID,
		RepositoryIds: repositoryIDs,
		Retries:       &entities.Retries{Attempts: 0},
		Tracking:      &entities.Tracking{TriggeredAt: timestamppb.Now()},
	}

	headers := make(map[string]string)
	otel.GetTextMapPropagator().Inject(ctx, propagation.MapCarrier(headers))
	tenancy.Inject(tenant, headers)

	err = s.publisher.Publish(msg, hydro.WithTopic(deleteUserRepositoriesTopic), hydro.WithCustomHeaders(headers))
	s.metrics.Send(ctx, "delete_user_repositories", err, metricspkg.WithHydroKey())

	if err != nil {
		logger.Error("Unable to publish the message")
		return nil, err
	}

	return &emptypb.Empty{}, nil
}
