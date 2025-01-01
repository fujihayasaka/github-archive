package mobile

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"github.com/Masterminds/squirrel"
	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/go-exceptions"
	"github.com/github/go-stats"
	stats_mock "github.com/github/go-stats/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/suite"
	"google.golang.org/protobuf/proto"
	pbany "google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"

	schemas_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	entities_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/mobile/clients"
	"github.com/github/notifyd/internal/mobile/layout/basic"
	"github.com/github/notifyd/internal/pkg/deliverytracking"
	"github.com/github/notifyd/internal/pkg/devicetokens"
	"github.com/github/notifyd/internal/pkg/dotcom/policy"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
	mobile_layouts "github.com/github/notifyd/proto/layouts/mobile"
)

type testSuite struct {
	suite.Suite
	reporter    *exceptions.Reporter
	db          mysql.DB
	dbCleanup   func()
	pushMock    *clients.MobileMock
	checkerMock *policy.CheckerMock
	ctx         context.Context
	trackerMock *deliverytracking.DeliveryTrackerMock
	clock       clockpkg.Clock
}

func (s *testSuite) SetupSuite() {
	s.prepareDB(context.Background())
}

func (s *testSuite) TearDownSuite() {
	if s.db.Write == nil {
		return
	}

	ctx := context.Background()
	if err := testhelper.TruncateAllTables(ctx, s.db); err != nil {
		panic(fmt.Sprintf("truncate test db: %s", err))
	}

	s.dbCleanup()
}

func (s *testSuite) SetupTest() {
	s.reporter = exceptions.NullReporter
	s.pushMock = new(clients.MobileMock)
	s.checkerMock = policy.NewCheckerMock(s.T())
	s.ctx = context.Background()
	s.clock = clockpkg.NewMock()
	s.resetDB(s.ctx)
	s.trackerMock = deliverytracking.NewDeliveryTrackerMock(s.T())
}

func (s *testSuite) prepareDB(ctx context.Context) {
	s.db, s.dbCleanup = testhelper.PrepareTestDB(ctx)
}

func (s *testSuite) resetDB(ctx context.Context) {
	s.T().Helper()

	tables := []string{"mobile_device_tokens"}
	err := testhelper.TruncateTables(ctx, s.db, tables)
	s.Require().NoError(err)
}

func (s *testSuite) TestHandleMessageForExistingDeviceTokens() {
	recipientID := int64(1)

	s.checkerMock.
		On("CanDeliverPushNotification", mock.Anything, tenancy.SingleTenant{}, int64(1), false, int64(1), int64(0), []string{"mention"}).
		Return(policy.CheckResult{IsDeliverable: true}, nil)

	tests := []struct {
		name            string
		attemptedTokens devicetokens.Tokens
		notifiedTokens  []string
	}{
		{
			name: "there is one device token associated to the user",
			attemptedTokens: devicetokens.Tokens{
				{ID: 1, UserID: recipientID, DeviceToken: "device-token-1"},
			},
			notifiedTokens: []string{"device-token-1"},
		},
		{
			name: "when the user has more then one device token",
			attemptedTokens: devicetokens.Tokens{
				{ID: 1, UserID: recipientID, DeviceToken: "device-token-1"},
				{ID: 2, UserID: recipientID, DeviceToken: "device-token-2"},
			},
			notifiedTokens: []string{"device-token-1", "device-token-2"},
		},
		{
			name: "there are multiple device tokens associated to multiple users",
			attemptedTokens: devicetokens.Tokens{
				{ID: 1, UserID: recipientID, DeviceToken: "device-token-1"},
				{ID: 2, UserID: 2, DeviceToken: "device-token-2"},
			},
			notifiedTokens: []string{"device-token-1"},
		},
	}

	handler := NewHandler(
		s.clock,
		logs.NullTelem,
		stats.NullStatter,
		s.pushMock,
		devicetokens.NewStorage(s.clock, logs.NullTelem, stats.NullStatter, s.db),
		s.checkerMock,
		s.trackerMock,
	)

	msg := s.buildDeliverMobilePush([]string{"mention"}, recipientID, time.Now())
	expectedNotification := clients.Notification{
		NotificationID: "notification-id",
		UserID:         recipientID,
		Title:          "@mikrobi mentioned you",
		Body:           "bold text",
		SubTitle:       "github/notifyd #1",
		URL:            "https://github.com/github/notifyd/issues/1#comment-123",
		Type:           "mention",
	}

	for _, test := range tests {
		s.Run(test.name, func() {
			ctx := s.ctx
			s.resetDB(ctx)
			s.insertTokens(ctx, test.attemptedTokens)
			var notifiedTokens devicetokens.Tokens
			for _, token := range test.attemptedTokens {
				for _, notified := range test.notifiedTokens {
					if token.DeviceToken == notified {
						notifiedTokens = append(notifiedTokens, token)
					}
				}
			}
			s.pushMock.On("SendNotification", expectedNotification, notifiedTokens).Return(nil)
			s.trackerMock.On("Track", mock.Anything, mock.Anything).Return(nil)
			err := handler.Run(ctx, tenancy.NewSingleTenant(), msg)
			s.Require().NoError(err, "Should return nil if message handled successfully")

			s.pushMock.AssertExpectations(s.T())
		})
	}
}

func (s *testSuite) TestHandleMessageForNonExistingDeviceTokens() {
	tests := []struct {
		name   string
		tokens devicetokens.Tokens
	}{
		{
			name: "when there are no tokens for the recipient user",
		},
		{
			name: "when there's a token for a user which is not the recipient",
			tokens: devicetokens.Tokens{
				{UserID: 2, DeviceToken: "device-token-2"},
			},
		},
	}

	handler := NewHandler(
		s.clock,
		logs.NullTelem,
		stats.NullStatter,
		s.pushMock,
		devicetokens.NewStorage(s.clock, logs.NullTelem, stats.NullStatter, s.db),
		s.checkerMock,
		s.trackerMock,
	)

	msg := s.buildDeliverMobilePush([]string{"mention"}, 1, time.Now())

	for _, test := range tests {
		s.Run(test.name, func() {
			ctx := s.ctx
			s.resetDB(ctx)
			s.insertTokens(ctx, test.tokens)

			err := handler.Run(ctx, tenancy.NewSingleTenant(), msg)
			s.Require().NoError(err, "Should return nil if message handled successfully")
			s.pushMock.AssertNotCalled(s.T(), "SendNotification")
		})
	}
}

func (s *testSuite) TestHandleMessageNotifiesDeviceTokensPassingPolicy() {
	ctx := s.ctx
	userID := int64(1)
	tokens := devicetokens.Tokens{
		{
			ID:            1,
			UserID:        userID,
			DeviceToken:   "device-token-1",
			OauthAccessID: 1,
		},
		{
			ID:            2,
			UserID:        userID,
			DeviceToken:   "device-token-2",
			OauthAccessID: 2,
		},
		{
			ID:            3,
			UserID:        userID,
			DeviceToken:   "device-token-3",
			OauthAccessID: 3,
		},
	}
	s.insertTokens(ctx, tokens)

	handler := NewHandler(
		s.clock,
		logs.NullTelem,
		stats.NullStatter,
		s.pushMock,
		devicetokens.NewStorage(s.clock, logs.NullTelem, stats.NullStatter, s.db),
		s.checkerMock,
		s.trackerMock,
	)

	reasons := []string{"mention"}
	msg := s.buildDeliverMobilePush(reasons, userID, time.Now())
	mockPolicyCheck := func(token devicetokens.Token, result policy.CheckResult, err error) {
		s.checkerMock.On("CanDeliverPushNotification", mock.Anything, mock.Anything, userID, msg.SamlEnforcement.SkipEnforcement, int64(msg.SamlEnforcement.OrganizationId), token.OauthAccessID, reasons).Return(result, err)
	}

	mockPolicyCheck(tokens[0], policy.CheckResult{IsDeliverable: true}, nil)
	mockPolicyCheck(tokens[1], policy.CheckResult{IsDeliverable: false, NotDeliverableReason: "rejected"}, nil)
	mockPolicyCheck(tokens[2], policy.CheckResult{}, errors.New("Error calling twirp api"))

	s.trackerMock.On("Track", mock.Anything, mock.Anything).Return(nil)
	s.pushMock.On("SendNotification", mock.Anything, tokens[:1]).Return(nil)

	err := handler.Run(ctx, tenancy.NewSingleTenant(), msg)
	s.Require().NoError(err)

	s.pushMock.AssertExpectations(s.T())
}

func (s *testSuite) TestHandleMessageLogsTimeToSentMetric() {
	ctx := s.ctx
	s.resetDB(ctx)

	s.checkerMock.
		On("CanDeliverPushNotification", mock.Anything, tenancy.SingleTenant{}, int64(1), false, int64(1), int64(1), []string{"mention"}).
		Return(policy.CheckResult{IsDeliverable: true}, nil)

	clock := clockpkg.NewMock()

	s.Run("logs delivery.time_to_sent metric", func() {
		tokens := devicetokens.Tokens{
			{
				ID:            1,
				UserID:        1,
				DeviceToken:   "device-token-1",
				OauthAccessID: 1,
			},
		}
		s.resetDB(ctx)
		s.insertTokens(ctx, tokens)

		statter := stats_mock.NewClient(s.T())
		statter.On("WithTags", mock.Anything).Return(statter)
		s.trackerMock.On("Track", mock.Anything, mock.Anything).Return(nil)
		triggeredAt := time.Now()

		handler := NewHandler(
			clock,
			logs.NullTelem,
			statter,
			s.pushMock,
			devicetokens.NewStorage(clock, logs.NullTelem, stats.NullStatter, s.db),
			s.checkerMock,
			s.trackerMock,
		)
		s.pushMock.On("SendNotification", mock.Anything, tokens[:1]).Return(nil)

		msg := s.buildDeliverMobilePush([]string{"mention"}, 1, triggeredAt)

		statter.On("Counter", mock.Anything, mock.Anything, mock.Anything)
		statter.On("DistributionMs", "delivery.time_to_sent", mock.Anything, mock.Anything)
		statter.On("DistributionMs", statsTimingKey, mock.Anything, mock.Anything)

		err := handler.Run(ctx, tenancy.NewSingleTenant(), msg)
		s.Require().NoError(err)
	})

	s.Run("does not log delivery.time_to_sent metric when triggered_at is nil", func() {
		tokens := devicetokens.Tokens{
			{
				ID:            1,
				UserID:        1,
				DeviceToken:   "device-token-2",
				OauthAccessID: 1,
			},
		}
		s.resetDB(ctx)
		s.insertTokens(ctx, tokens)

		statter := stats_mock.NewClient(s.T())
		statter.On("WithTags", mock.Anything).Return(statter)
		handler := NewHandler(
			clock,
			logs.NullTelem,
			statter,
			s.pushMock,
			devicetokens.NewStorage(clock, logs.NullTelem, stats.NullStatter, s.db),
			s.checkerMock,
			s.trackerMock,
		)
		s.pushMock.On("SendNotification", mock.Anything, tokens[:1]).Return(nil)

		msg := &schemas_pb.DeliverMobilePush{
			NotificationId: "notification-id",
			UserId:         1,
			Reasons:        reasonsToStructs([]string{"mention"}),
			LayoutData: &pbany.Any{
				TypeUrl: basic.TypeURL,
				Value:   s.buildBasicLayout(),
			},
			SamlEnforcement: &entities_pb.SamlEnforcement{
				SkipEnforcement: false,
				OrganizationId:  1,
			},
			Tracking: &entities_pb.Tracking{
				TriggeredAt: nil,
			},
		}

		statter.On("Counter", mock.Anything, mock.Anything, mock.Anything)
		statter.On("DistributionMs", statsTimingKey, mock.Anything, mock.Anything)
		statter.AssertNotCalled(s.T(), "DistributionMs", "delivery.time_to_sent")

		err := handler.Run(ctx, tenancy.NewSingleTenant(), msg)
		s.Require().NoError(err)
	})

	s.Run("does not log delivery.time_to_sent metric when tracking field is not provided", func() {
		tokens := devicetokens.Tokens{
			{
				ID:            1,
				UserID:        1,
				DeviceToken:   "device-token-3",
				OauthAccessID: 1,
			},
		}
		s.resetDB(ctx)
		s.insertTokens(ctx, tokens)

		statter := stats_mock.NewClient(s.T())
		statter.On("WithTags", mock.Anything).Return(statter)

		handler := NewHandler(
			clock,
			logs.NullTelem,
			statter,
			s.pushMock,
			devicetokens.NewStorage(clock, logs.NullTelem, stats.NullStatter, s.db),
			s.checkerMock,
			s.trackerMock,
		)
		s.pushMock.On("SendNotification", mock.Anything, tokens[:1]).Return(nil)

		msg := &schemas_pb.DeliverMobilePush{
			NotificationId: "notification-id",
			UserId:         1,
			Reasons:        reasonsToStructs([]string{"mention"}),
			LayoutData: &pbany.Any{
				TypeUrl: basic.TypeURL,
				Value:   s.buildBasicLayout(),
			},
			SamlEnforcement: &entities_pb.SamlEnforcement{
				SkipEnforcement: false,
				OrganizationId:  1,
			},
		}

		statter.On("Counter", mock.Anything, mock.Anything, mock.Anything)
		statter.On("DistributionMs", statsTimingKey, mock.Anything, mock.Anything)
		statter.AssertNotCalled(s.T(), "DistributionMs")

		err := handler.Run(ctx, tenancy.NewSingleTenant(), msg)
		s.Require().NoError(err)
	})
}

func (s *testSuite) TestLogDeliveredNotifications() {
	ctx := s.ctx
	s.resetDB(ctx)

	s.checkerMock.
		On("CanDeliverPushNotification", mock.Anything, tenancy.SingleTenant{}, int64(1), false, int64(1), int64(1), []string{"mention"}).
		Return(policy.CheckResult{IsDeliverable: true}, nil)

	s.Run("logs delivered notifications to hydro", func() {
		tokens := devicetokens.Tokens{
			{
				ID:            1,
				UserID:        1,
				DeviceToken:   "device-token-1",
				OauthAccessID: 1,
			},
			{
				ID:            2,
				UserID:        1,
				DeviceToken:   "device-token-2",
				OauthAccessID: 1,
			},
		}
		s.resetDB(ctx)
		s.insertTokens(ctx, tokens)

		clock := clockpkg.NewMock()
		handler := NewHandler(
			clock,
			logs.NullTelem,
			stats.NullStatter,
			s.pushMock,
			devicetokens.NewStorage(clock, logs.NullTelem, stats.NullStatter, s.db),
			s.checkerMock,
			s.trackerMock,
		)
		s.pushMock.On("SendNotification", mock.Anything, tokens).Return(nil)

		msg := s.buildDeliverMobilePush([]string{"mention", "assign"}, 1, time.Now())

		s.trackerMock.On("Track", mock.Anything, mock.MatchedBy(func(m *schemas_pb.DeliveredNotification) bool {
			return proto.Equal(m, &schemas_pb.DeliveredNotification{
				UserId:         msg.GetUserId(),
				NotificationId: msg.GetNotificationId(),
				Reasons:        []*entities_pb.Reason{{Name: "mention"}},
				Channel:        entities_pb.Channel_MOBILE_PUSH,
				Token:          "device-token-1",
				Tracking:       msg.GetTracking(),
			}) || proto.Equal(m, &schemas_pb.DeliveredNotification{
				UserId:         msg.GetUserId(),
				NotificationId: msg.GetNotificationId(),
				Reasons:        []*entities_pb.Reason{{Name: "mention"}},
				Channel:        entities_pb.Channel_MOBILE_PUSH,
				Token:          "device-token-2",
				Tracking:       msg.GetTracking(),
			})
		})).Return(nil)

		err := handler.Run(ctx, tenancy.NewSingleTenant(), msg)
		s.Require().NoError(err)
	})
}

func Test_MobileHandlerSuite(t *testing.T) {
	suite.Run(t, new(testSuite))
}

// insertTokens adds an array of devicetokens.DeviceToken on the database and
// asserts no errors happened for each one.
func (s *testSuite) insertTokens(ctx context.Context, tokens devicetokens.Tokens) {
	s.T().Helper()

	for _, token := range tokens {
		s.insertToken(ctx, token)
	}
}

// insertTokens adds a single devicetokens.DeviceToken on the database and
// returns it and asserts no errors happened.
func (s *testSuite) insertToken(ctx context.Context, token devicetokens.Token) {
	s.T().Helper()

	ts := mysql.NewTimestamps(s.clock)
	insert := squirrel.Insert("mobile_device_tokens").
		Columns("id", "user_id", "device_token", "oauth_access_id", "created_at", "updated_at").
		Values(
			token.ID,
			token.UserID,
			token.DeviceToken,
			token.OauthAccessID,
			ts.CreatedAt,
			ts.UpdatedAt,
		)

	sql, args, err := insert.ToSql()
	s.Require().NoError(err)

	_, err = s.db.Write.ExecContext(ctx, sql, args...)
	s.Require().NoError(err)
}

// buildBasicLayout builds and marshal the layout for a
// mentionable comment.
func (s *testSuite) buildBasicLayout() []byte {
	s.T().Helper()

	layoutData := mobile_layouts.Basic{
		Title:    "@mikrobi mentioned you",
		Subtitle: "github/notifyd #1",
		Body:     "<b>bold text</b>",
		Url:      "https://github.com/github/notifyd/issues/1#comment-123",
	}

	layoutBytes, err := proto.Marshal(&layoutData)
	s.Require().NoError(err)

	return layoutBytes
}

// buildDeliverMobilePush builds a message for the hydro consumer
func (s *testSuite) buildDeliverMobilePush(reasonNames []string, userID int64, triggeredAtTime time.Time) *schemas_pb.DeliverMobilePush {
	reasons := reasonsToStructs(reasonNames)
	layout := s.buildBasicLayout()

	return &schemas_pb.DeliverMobilePush{
		NotificationId: "notification-id",
		UserId:         int32(userID),
		Reasons:        reasons,
		LayoutData: &pbany.Any{
			TypeUrl: basic.TypeURL,
			Value:   layout,
		},
		SamlEnforcement: &entities_pb.SamlEnforcement{
			SkipEnforcement: false,
			OrganizationId:  int32(1),
		},
		Tracking: &entities_pb.Tracking{
			TriggeredAt: timestamppb.New(triggeredAtTime),
			SubjectMetadata: &entities_pb.Tracking_SubjectMetadata{
				ListType:    "Repository",
				ListId:      "123",
				ThreadType:  "Issue",
				ThreadId:    "456",
				CommentType: "Issue",
				CommentId:   "789",
			},
		},
	}
}

// reasonsToStructs transforms an array of strings with reason names into an
// array of notifydEntities.Reason to build a hydro message
func reasonsToStructs(reasons []string) []*entities_pb.Reason {
	structs := make([]*entities_pb.Reason, len(reasons))
	for idx, reason := range reasons {
		structs[idx] = &entities_pb.Reason{Name: reason}
	}

	return structs
}
