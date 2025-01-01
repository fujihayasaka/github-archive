package maintenanceserver

import (
	"context"
	"errors"
	"testing"

	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
	testsuite "github.com/stretchr/testify/suite"

	hydropb "github.com/github/notifyd/hydro/schemas/notifyd/v1"
	"github.com/github/notifyd/internal/pkg/job/metrics"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
	apipb "github.com/github/notifyd/proto/services/maintenance"
)

type suite struct {
	testsuite.Suite
}

func TestSuite(t *testing.T) {
	testsuite.Run(t, new(suite))
}

func (s *suite) TestDeleteRepository_InvalidRepositoryID() {
	publisher := &PublisherMock{}

	telem := logs.NullTelem
	server := NewServer(publisher, telem, metrics.NewPublisherMetrics(telem, stats.NullStatter))

	req := &apipb.DeleteRepositoryRequest{RepositoryId: 0}
	ctx := tenancy.ContextWithTenant(context.Background(), tenancy.NewSingleTenant())

	_, err := server.DeleteRepository(ctx, req)
	s.Require().ErrorContains(err, "invalid repository ID")

	publisher.AssertNotCalled(s.T(), "Publish")
}

func (s *suite) TestDeleteRepository_NoTenant() {
	publisher := &PublisherMock{}

	telem := logs.NullTelem
	server := NewServer(publisher, telem, metrics.NewPublisherMetrics(telem, stats.NullStatter))

	req := &apipb.DeleteRepositoryRequest{RepositoryId: 1}

	_, err := server.DeleteRepository(context.Background(), req)
	s.Require().ErrorContains(err, "no tenant")

	publisher.AssertNotCalled(s.T(), "Publish")
}

func (s *suite) TestDeleteRepository_PublishError() {
	publisher := &PublisherMock{}
	// Check that hydro publisher is called with a message containing the expected repository ID and return an error
	publisher.On("Publish", mock.MatchedBy(func(msg *hydropb.DeleteRepository) bool {
		return msg.RepositoryId == 1
	}), mock.Anything, mock.Anything).Return(errors.New("an error"))

	telem := logs.NullTelem
	server := NewServer(publisher, telem, metrics.NewPublisherMetrics(telem, stats.NullStatter))

	req := &apipb.DeleteRepositoryRequest{RepositoryId: 1}
	ctx := tenancy.ContextWithTenant(context.Background(), tenancy.NewSingleTenant())

	_, err := server.DeleteRepository(ctx, req)
	s.Require().ErrorContains(err, "an error")
}

func (s *suite) TestDeleteUserRepositories_InvalidUserID() {
	publisher := &PublisherMock{}

	telem := logs.NullTelem
	server := NewServer(publisher, telem, metrics.NewPublisherMetrics(telem, stats.NullStatter))

	req := &apipb.DeleteUserRepositoriesRequest{UserId: 0, RepositoryIds: []int64{123}}
	ctx := tenancy.ContextWithTenant(context.Background(), tenancy.NewSingleTenant())

	_, err := server.DeleteUserRepositories(ctx, req)
	s.Require().ErrorContains(err, "invalid user ID")

	publisher.AssertNotCalled(s.T(), "Publish")
}

func (s *suite) TestDeleteUserRepositories_InvalidRepositoryCount() {
	publisher := &PublisherMock{}

	telem := logs.NullTelem
	server := NewServer(publisher, telem, metrics.NewPublisherMetrics(telem, stats.NullStatter))

	req := &apipb.DeleteUserRepositoriesRequest{UserId: 1, RepositoryIds: []int64{}}
	ctx := tenancy.ContextWithTenant(context.Background(), tenancy.NewSingleTenant())

	_, err := server.DeleteUserRepositories(ctx, req)
	s.Require().ErrorContains(err, "no repository IDs provided for userID: 1")

	publisher.AssertNotCalled(s.T(), "Publish")
}

func (s *suite) TestMaintenance_Success_DeleteRepository() {
	publisher := NewPublisherMock(s.T())
	// Check that hydro publisher is called with a message containing the expected repository ID
	publisher.On("Publish", mock.MatchedBy(func(msg *hydropb.DeleteRepository) bool {
		return msg.RepositoryId == 1
	}), mock.Anything, mock.Anything).Return(nil)

	telem := logs.NullTelem
	server := NewServer(publisher, telem, metrics.NewPublisherMetrics(telem, stats.NullStatter))

	req := &apipb.DeleteRepositoryRequest{RepositoryId: 1}
	ctx := tenancy.ContextWithTenant(context.Background(), tenancy.NewSingleTenant())

	_, err := server.DeleteRepository(ctx, req)
	s.Require().NoError(err)
}

func (s *suite) TestMaintenance_Success_DeleteUser() {
	publisher := NewPublisherMock(s.T())
	// Check that hydro publisher is called with a message containing the expected repository ID
	publisher.On("Publish", mock.MatchedBy(func(msg *hydropb.DeleteUser) bool {
		return msg.UserId == 1
	}), mock.Anything, mock.Anything).Return(nil)

	telem := logs.NullTelem
	server := NewServer(publisher, telem, metrics.NewPublisherMetrics(telem, stats.NullStatter))

	req := &apipb.DeleteUserRequest{UserId: 1}
	ctx := tenancy.ContextWithTenant(context.Background(), tenancy.NewSingleTenant())

	_, err := server.DeleteUser(ctx, req)
	s.Require().NoError(err)
}

func (s *suite) TestMaintenance_Success_DeleteUserRepositories() {
	publisher := NewPublisherMock(s.T())
	// Check that hydro publisher is called with a message containing the expected repository ID
	publisher.On("Publish", mock.MatchedBy(func(msg *hydropb.DeleteUserRepositories) bool {
		return msg.UserId == 1 && msg.RepositoryIds[0] == 123
	}), mock.Anything, mock.Anything).Return(nil)

	telem := logs.NullTelem
	server := NewServer(publisher, telem, metrics.NewPublisherMetrics(telem, stats.NullStatter))

	req := &apipb.DeleteUserRepositoriesRequest{UserId: 1, RepositoryIds: []int64{123}}
	ctx := tenancy.ContextWithTenant(context.Background(), tenancy.NewSingleTenant())

	_, err := server.DeleteUserRepositories(ctx, req)
	s.Require().NoError(err)
}

func (s *suite) TestMaintenance_Success_DeleteRepositoryForUsers() {
	publisher := NewPublisherMock(s.T())
	// Check that hydro publisher is called with a message containing the expected repository ID
	publisher.On("Publish", mock.MatchedBy(func(msg *hydropb.DeleteRepositoryForUsers) bool {
		return msg.RepositoryId == 123 && msg.UserIds[0] == 1
	}), mock.Anything, mock.Anything).Return(nil)

	telem := logs.NullTelem
	server := NewServer(publisher, telem, metrics.NewPublisherMetrics(telem, stats.NullStatter))

	req := &apipb.DeleteRepositoryForUsersRequest{RepositoryId: 123, UserIds: []int64{1}}
	ctx := tenancy.ContextWithTenant(context.Background(), tenancy.NewSingleTenant())

	_, err := server.DeleteRepositoryForUsers(ctx, req)
	s.Require().NoError(err)
}
