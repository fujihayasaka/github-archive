package newsiesserver

import (
	"context"
	"testing"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/stretchr/testify/suite"

	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"

	"github.com/github/notifyd/internal/api/newsiesservice"
	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	pb "github.com/github/notifyd/proto/services/newsies"
)

type IntegrationSuite struct {
	suite.Suite
	testhelper.DatabaseSuite
}

func Test_Integration(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping integration tests in fast run")
	}

	suite.Run(t, new(IntegrationSuite))
}

func (s *IntegrationSuite) Test_IgnoreWatch() {
	ctx := context.Background()
	userID := s.SequentialIDs().Get()

	s.assertIgnore(ctx, userID)
	s.assertWatch(ctx, userID)
}

func (s *IntegrationSuite) Test_WatchUnwatch() {
	ctx := context.Background()
	userID := s.SequentialIDs().Get()

	s.assertWatch(ctx, userID)
	s.assertUnwatch(ctx, userID)
}

func (s *IntegrationSuite) Test_UnwatchMultiple() {
	ctx := context.Background()
	userID := s.SequentialIDs().Get()

	s.assertWatchMultiple(ctx, userID)
	s.assertUnwatchMultiple(ctx, userID)
}

func (s *IntegrationSuite) Test_IgnoreUnwatch() {
	ctx := context.Background()
	userID := s.SequentialIDs().Get()

	s.assertIgnore(ctx, userID)
	s.assertUnwatch(ctx, userID)
}

func (s *IntegrationSuite) assertQueryCount(want int, query string, args ...any) {
	s.T().Helper()

	r := s.Require()
	db := s.DB().Read
	rows, err := db.Queryx(query, args...)
	r.NoError(err)
	defer rows.Close()

	if rows.Next() {
		var got int
		err = rows.Scan(&got)

		r.NoError(err, query)
		r.Equal(want, got, query, args)
	}
}

func (s *IntegrationSuite) newWatchRequest(userID, refID int64) *pb.WatchRequest {
	s.T().Helper()

	return &pb.WatchRequest{
		UserId:      userID,
		RefId:       refID,
		RefType:     "Repository",
		ThreadTypes: []pb.ThreadTypes{},
		CustomFields: []*pb.CustomField{
			{Name: "owner_type", Value: "user"},
			{Name: "owner_id", Value: "1"},
		},
	}
}

func (s *IntegrationSuite) newUnwatchRequest(userID int64) *pb.UnwatchRequest {
	s.T().Helper()

	return &pb.UnwatchRequest{UserId: userID, RefId: 1, RefType: "Repository"}
}

func (s *IntegrationSuite) newUnwatchMultipleRequest(userID int64, refIDs []int64) *pb.UnwatchRequest {
	s.T().Helper()

	return &pb.UnwatchRequest{UserId: userID, RefIds: refIDs, RefType: "Repository"}
}

func (s *IntegrationSuite) newIgnoreRequest(userID int64) *pb.IgnoreRequest {
	s.T().Helper()

	return &pb.IgnoreRequest{
		UserId:  userID,
		RefId:   1,
		RefType: "Repository",
		CustomFields: []*pb.CustomField{
			{Name: "owner_type", Value: "user"},
			{Name: "owner_id", Value: "1"},
		},
	}
}

func newServer(s *IntegrationSuite) *Server {
	s.T().Helper()

	db := s.DB()
	statter := stats.NullStatter
	telem := logs.NullTelem
	clock := clockpkg.NewMock()

	settingsStorage := routing.NewStorage(clock, telem, db)
	settingsService := routing.NewSettingsService(settingsStorage, telem, statter)

	subscriptionsStorage := subscriptions.NewStorage(clock, telem, db)
	subscriptionsService := subscriptions.NewService(subscriptionsStorage, telem, statter)

	newsiesService := newsiesservice.NewService(settingsService, subscriptionsService, statter, clock)
	return New(newsiesService, logs.NullTelem)
}

func (s *IntegrationSuite) assertIgnore(ctx context.Context, userID int64) {
	s.T().Helper()
	s.T().Log("Ignore")
	srv := newServer(s)
	_, err := srv.Ignore(ctx, s.newIgnoreRequest(userID))
	s.Require().NoError(err)
	s.assertQueryCount(0, "select count(*) from meta_subscriptions where user_id=?", userID)
	s.assertQueryCount(1, "select count(*) from meta_routing_settings where user_id=?", userID)
}

func (s *IntegrationSuite) assertWatch(ctx context.Context, userID int64) {
	s.T().Helper()
	s.T().Log("Watch")
	srv := newServer(s)
	_, err := srv.Watch(ctx, s.newWatchRequest(userID, 1))
	s.Require().NoError(err)
	s.assertQueryCount(1, "select count(*) from meta_subscriptions where user_id=?", userID)
	s.assertQueryCount(0, "select count(*) from meta_routing_settings where user_id=?", userID)
}

func (s *IntegrationSuite) assertUnwatch(ctx context.Context, userID int64) {
	s.T().Helper()
	s.T().Log("Unwatch")
	srv := newServer(s)
	_, err := srv.Unwatch(ctx, s.newUnwatchRequest(userID))
	s.Require().NoError(err)
	s.assertQueryCount(0, "select count(*) from meta_subscriptions where user_id=?", userID)
	s.assertQueryCount(0, "select count(*) from meta_routing_settings where user_id=?", userID)
}

func (s *IntegrationSuite) assertWatchMultiple(ctx context.Context, userID int64) {
	s.T().Helper()
	s.T().Log("Watch")
	srv := newServer(s)
	_, err := srv.Watch(ctx, s.newWatchRequest(userID, 1))
	s.Require().NoError(err)
	_, err = srv.Watch(ctx, s.newWatchRequest(userID, 2))
	s.Require().NoError(err)
	s.assertQueryCount(2, "select count(*) from meta_subscriptions where user_id=?", userID)
	s.assertQueryCount(0, "select count(*) from meta_routing_settings where user_id=?", userID)
}

func (s *IntegrationSuite) assertUnwatchMultiple(ctx context.Context, userID int64) {
	s.T().Helper()
	s.T().Log("Unwatch")
	srv := newServer(s)
	_, err := srv.Unwatch(ctx, s.newUnwatchMultipleRequest(userID, []int64{1, 2}))
	s.Require().NoError(err)
	s.assertQueryCount(0, "select count(*) from meta_subscriptions where user_id=?", userID)
	s.assertQueryCount(0, "select count(*) from meta_routing_settings where user_id=?", userID)
}
