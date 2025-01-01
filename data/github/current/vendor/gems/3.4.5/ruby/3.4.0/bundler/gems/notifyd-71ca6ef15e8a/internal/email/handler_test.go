package email

import (
	"context"
	gomail "net/mail"
	"testing"
	"time"

	"github.com/benbjohnson/clock"
	ghstats "github.com/github/go-stats"
	stats_mock "github.com/github/go-stats/mocks"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"

	schemaspb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	entitiespb "github.com/github/notifyd/hydro/schemas/notifyd/v0/entities"
	"github.com/github/notifyd/internal/email/datastructures"
	"github.com/github/notifyd/internal/email/header"
	"github.com/github/notifyd/internal/email/layout/basic"
	"github.com/github/notifyd/internal/email/layout/config"
	"github.com/github/notifyd/internal/email/layout/raw"
	"github.com/github/notifyd/internal/email/pipeline"
	"github.com/github/notifyd/internal/pkg/deliverytracking"
	"github.com/github/notifyd/internal/pkg/dotcom/policy"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/tenancy"
	email_layout "github.com/github/notifyd/proto/layouts/email"
)

func Test_RunBasic(t *testing.T) {
	t.Run("works", func(t *testing.T) {
		r := require.New(t)
		ctx := context.Background()

		msg := &schemaspb.DeliverEmail{
			UserId:         1,
			Reasons:        []*entitiespb.Reason{{Name: "mention"}},
			LayoutData:     getBasicLayoutData(t),
			NotificationId: "notification-id",
			SubjectType:    "Issue",
			Tracking:       getTracking(t, time.Now()),
			OrganizationId: wrapperspb.Int64(9919),
			MatchData:      getMatchData(t),
		}
		tests := []struct {
			name        string
			checkResult datastructures.DeliverEmailData
			counterTags ghstats.Tags
		}{
			{
				name: "when the email is deliverable",
				checkResult: datastructures.DeliverEmailData{
					IsDeliverable: true,
					Email:         "test@email.com",
					AuthTokens: []datastructures.AuthToken{
						{Scope: datastructures.MuteAuthScope, Token: "token_value1"},
						{Scope: datastructures.MuteListScope, Token: "token_value2"},
					},
				},
				counterTags: ghstats.Tags{"status": "succeeded", "subject_type": "Issue"},
			},
			{
				name:        "when the email is not deliverable",
				checkResult: datastructures.DeliverEmailData{IsDeliverable: false},
				counterTags: ghstats.Tags{"status": "skipped", "subject_type": "Issue", "reason": ""},
			},
		}

		for _, test := range tests {
			t.Run(test.name, func(t *testing.T) {
				var matchData structpb.Struct

				err := proto.Unmarshal(msg.MatchData.GetValue(), &matchData)
				r.NoError(err)

				checker := policy.NewCheckerMock(t)
				nid, _ := structpb.NewStruct(map[string]interface{}{
					"notification_id": msg.GetNotificationId(),
				})
				request := &policy.EmailDeliveryRequest{
					UserID:         1,
					OrganizationID: 9919,
					NotificationID: nid,
					MatchData:      &matchData,
				}
				checker.On("GetDeliverEmailData", mock.Anything, mock.Anything, request).Return(test.checkResult, nil)
				notification := datastructures.Notification{
					Subject: "subject",
					Body:    "<body>processed content</body>",
					CC:      header.NewAddressListField("Cc", []*gomail.Address{{Name: "Mention", Address: "mention@noreply.github.com"}}),
					From:    header.NewAddressField("From", &gomail.Address{Name: "GitHub", Address: "notifications@github.com"}),
					To:      header.NewAddressField("To", &gomail.Address{Address: "email_list@test.com"}),
					Header: &header.Header{
						Fields: []header.Field{
							header.NewTextField("X-GitHub-Reason", "mention"),
							header.ListUnsubscribe{URL: "https://github.com/notifications/unsubscribe/token_value2"},
						},
					},
					Recipient:      test.checkResult.Email,
					UnsubscribeURL: "https://github.com/notifications/unsubscribe-auth/token_value1",
				}
				emailer := NewSenderMock(t)
				deliveryTrackerMock := deliverytracking.NewDeliveryTrackerMock(t)
				emailProcessorMock := pipeline.NewPostProcessorMock(t)
				statsMock := stats_mock.NewClient(t)
				if test.checkResult.IsDeliverable {
					emailer.On("Send", mock.Anything, &notification).Return(nil)
					deliveryTrackerMock.On("Track", mock.Anything, mock.Anything).Return(nil)
					emailProcessorMock.On("Process", mock.Anything, mock.Anything, mock.Anything).Return("<body>processed content</body>", nil)
					statsMock.On("DistributionMs", "delivery.time_to_sent", mock.Anything, mock.AnythingOfType("time.Duration"))
				}
				statsMock.On("WithTags", ghstats.Tags{"type": "email"}).Return(statsMock)
				statsMock.On("DistributionMs", "deliveremail.stages.time", mock.Anything, mock.AnythingOfType("time.Duration"))
				statsMock.On("Counter", "delivery", test.counterTags, int64(1))

				ecfg := config.Config{SenderDomain: "github.com", FromAddressName: "notifications"}
				h := NewHandler(checker, emailer, deliveryTrackerMock, clock.NewMock(), logs.NullTelem, statsMock, ecfg, emailProcessorMock)
				err = h.Run(ctx, tenancy.NewSingleTenant(), msg)
				r.NoError(err)
			})
		}
	})
}

func Test_RunRaw(t *testing.T) {
	t.Run("works", func(t *testing.T) {
		r := require.New(t)
		ctx := context.Background()

		msg := &schemaspb.DeliverEmail{
			UserId:         1,
			Reasons:        []*entitiespb.Reason{{Name: "mention"}},
			SubjectType:    "Issue",
			LayoutData:     getRawLayoutData(t),
			NotificationId: "notification-id",
			Tracking:       getTracking(t, time.Now()),
			OrganizationId: wrapperspb.Int64(9919),
		}
		tests := []struct {
			name        string
			checkResult datastructures.DeliverEmailData
			counterTags ghstats.Tags
		}{
			{
				name:        "when the email is deliverable",
				checkResult: datastructures.DeliverEmailData{IsDeliverable: true, Email: "test@email.com"},
				counterTags: ghstats.Tags{"status": "succeeded", "subject_type": "Issue"},
			},
			{
				name:        "when the email is not deliverable",
				checkResult: datastructures.DeliverEmailData{IsDeliverable: false},
				counterTags: ghstats.Tags{"status": "skipped", "reason": "", "subject_type": "Issue"},
			},
		}

		for _, test := range tests {
			t.Run(test.name, func(t *testing.T) {
				var matchData structpb.Struct

				err := proto.Unmarshal(msg.MatchData.GetValue(), &matchData)
				r.NoError(err)

				checker := policy.NewCheckerMock(t)
				nid, _ := structpb.NewStruct(map[string]interface{}{
					"notification_id": msg.GetNotificationId(),
				})
				request := &policy.EmailDeliveryRequest{
					UserID:         1,
					OrganizationID: 9919,
					NotificationID: nid,
					MatchData:      &matchData,
				}
				checker.On("GetDeliverEmailData", mock.Anything, mock.Anything, request).Return(test.checkResult, nil)
				emailer := NewSenderMock(t)
				deliveryTrackerMock := deliverytracking.NewDeliveryTrackerMock(t)
				emailProcessorMock := pipeline.NewPostProcessorMock(t)
				statsMock := stats_mock.NewClient(t)
				if test.checkResult.IsDeliverable {
					emailer.On("Send", mock.Anything, mock.Anything).Return(nil)
					deliveryTrackerMock.On("Track", mock.Anything, mock.MatchedBy(func(m *schemaspb.DeliveredNotification) bool {
						return proto.Equal(m, &schemaspb.DeliveredNotification{
							UserId:         msg.GetUserId(),
							NotificationId: msg.GetNotificationId(),
							Reasons:        []*entitiespb.Reason{{Name: "mention"}},
							Channel:        entitiespb.Channel_EMAIL,
							Tracking:       msg.GetTracking(),
						})
					})).Return(nil)
					statsMock.On("DistributionMs", "delivery.time_to_sent", mock.Anything, mock.AnythingOfType("time.Duration"))
				}
				statsMock.On("WithTags", ghstats.Tags{"type": "email"}).Return(statsMock)
				statsMock.On("DistributionMs", "deliveremail.stages.time", mock.Anything, mock.AnythingOfType("time.Duration"))
				statsMock.On("Counter", "delivery", test.counterTags, int64(1))

				ecfg := config.Config{SenderDomain: "github.com", FromAddressName: "notifications"}
				h := NewHandler(checker, emailer, deliveryTrackerMock, clock.NewMock(), logs.NullTelem, statsMock, ecfg, emailProcessorMock)
				err = h.Run(ctx, tenancy.NewSingleTenant(), msg)
				r.NoError(err)
			})
		}
	})
}

func Test_Run_ErrorHandling(t *testing.T) {
	r := require.New(t)
	msg := &schemaspb.DeliverEmail{
		UserId:         1,
		Reasons:        []*entitiespb.Reason{{Name: "mention"}},
		SubjectType:    "Issue",
		LayoutData:     getBasicLayoutData(t),
		NotificationId: "notification-id",
		Tracking:       getTracking(t, time.Now()),
		OrganizationId: wrapperspb.Int64(9919),
		MatchData:      getMatchData(t),
	}

	tests := []struct {
		name        string
		msg         *schemaspb.DeliverEmail
		assert      func(*testing.T, error, map[string]error)
		errors      map[string]error
		counterTags ghstats.Tags
	}{
		{
			name: "when the policy check fails",
			msg:  msg,
			errors: map[string]error{
				"check": errors.New("error calling the notifyd monolith-twirp API"),
			},
			assert: func(t *testing.T, err error, errors map[string]error) {
				r.ErrorIs(err, errors["check"], "it propagates the error")
			},
			counterTags: ghstats.Tags{"status": "failed", "reason": "policy_check", "subject_type": "Issue"},
		},
		{
			name: "when the email delivery fails",
			msg:  msg,
			errors: map[string]error{
				"emailer": errors.New("error on email delivery"),
			},
			assert: func(t *testing.T, err error, errors map[string]error) {
				r.ErrorIs(err, errors["emailer"], "it propagates the error")
			},
			counterTags: ghstats.Tags{"status": "failed", "reason": "sending_email", "subject_type": "Issue"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			checker := new(policy.CheckerMock)
			checkResult := datastructures.DeliverEmailData{
				IsDeliverable: true,
				Email:         "test@email.com",
				AuthTokens: []datastructures.AuthToken{
					{Scope: datastructures.MuteAuthScope, Token: "token_value1"},
					{Scope: datastructures.MuteListScope, Token: "token_value2"},
				},
			}
			if test.errors["check"] != nil {
				checkResult = datastructures.DeliverEmailData{}
			}

			var matchData structpb.Struct
			err := proto.Unmarshal(msg.MatchData.GetValue(), &matchData)
			r.NoError(err)

			nid, _ := structpb.NewStruct(map[string]interface{}{
				"notification_id": msg.GetNotificationId(),
			})
			request := &policy.EmailDeliveryRequest{
				UserID:         1,
				OrganizationID: 9919,
				NotificationID: nid,
				MatchData:      &matchData,
			}
			checker.On("GetDeliverEmailData", mock.Anything, mock.Anything, request).Return(checkResult, test.errors["check"])

			emailer := new(SenderMock)
			notification := datastructures.Notification{
				Subject: "subject",
				Body:    "<body>processed content</body>",
				CC:      header.NewAddressListField("Cc", []*gomail.Address{{Name: "Mention", Address: "mention@noreply.github.com"}}),
				From:    header.NewAddressField("From", &gomail.Address{Name: "GitHub", Address: "notifications@github.com"}),
				To:      header.NewAddressField("To", &gomail.Address{Address: "email_list@test.com"}),
				Header: &header.Header{
					Fields: []header.Field{
						header.NewTextField("X-GitHub-Reason", "mention"),
						header.ListUnsubscribe{URL: "https://github.com/notifications/unsubscribe/token_value2"},
					},
				},
				Recipient:      checkResult.Email,
				UnsubscribeURL: "https://github.com/notifications/unsubscribe-auth/token_value1",
			}
			emailer.On("Send", mock.Anything, &notification).Return(test.errors["emailer"])
			deliveryTracking := new(deliverytracking.DeliveryTrackerMock)

			statsMock := new(stats_mock.Client)
			statsMock.On("WithTags", ghstats.Tags{"type": "email"}).Return(statsMock)
			statsMock.On("Counter", "delivery", test.counterTags, int64(1))
			statsMock.On("DistributionMs", "deliveremail.stages.time", mock.Anything, mock.AnythingOfType("time.Duration"))

			// Not all test cases execute this mock, so we can't use pipeline.NewPostProcessorMock
			emailProcessorMock := new(pipeline.PostProcessorMock)
			emailProcessorMock.On("Process", mock.Anything, mock.Anything, mock.Anything).Return("<body>processed content</body>", nil)

			ecfg := config.Config{SenderDomain: "github.com", FromAddressName: "notifications"}
			h := NewHandler(checker, emailer, deliveryTracking, clock.NewMock(), logs.NullTelem, statsMock, ecfg, emailProcessorMock)
			ctx := context.Background()
			err = h.Run(ctx, tenancy.NewSingleTenant(), test.msg)

			r.Error(err)
			test.assert(t, err, test.errors)
			deliveryTracking.AssertNotCalled(t, "Track")
		})
	}
}

func getTracking(t *testing.T, now time.Time) *entitiespb.Tracking {
	t.Helper()

	return &entitiespb.Tracking{
		TriggeredAt: timestamppb.New(now),
		SubjectMetadata: &entitiespb.Tracking_SubjectMetadata{
			ListType:    "Repository",
			ListId:      "123",
			ThreadType:  "Issue",
			ThreadId:    "456",
			CommentType: "Issue",
			CommentId:   "789",
		},
	}
}

func getBasicLayoutData(t *testing.T) *anypb.Any {
	t.Helper()

	layout := email_layout.Basic{
		Subject: "subject",
		Body:    "body",
		To:      "email_list@test.com",
		UnsubscribeUrlTemplates: &email_layout.UnsubscribeUrlTemplates{
			Footer: "https://github.com/notifications/unsubscribe-auth/{token}",
			Header: "https://github.com/notifications/unsubscribe/{token}",
		}}
	value, err := proto.Marshal(&layout)
	require.NoError(t, err)

	return &anypb.Any{
		TypeUrl: basic.TypeURL,
		Value:   value,
	}
}

func getMatchData(t *testing.T) *anypb.Any {
	matchData, err := structpb.NewStruct(map[string]interface{}{
		"subject_type": "GistComment",
		"attributes": []interface{}{
			map[string]interface{}{"name": "thread_id", "value": "123"},
		},
	})

	require.NoError(t, err)

	value, err := proto.Marshal(matchData)
	require.NoError(t, err)

	return &anypb.Any{
		TypeUrl: "google.protobuf.Struct",
		Value:   value,
	}
}

func getRawLayoutData(t *testing.T) *anypb.Any {
	t.Helper()

	layout := email_layout.Raw{Subject: "subject", Body: []*email_layout.Part{{Content: "body"}}, To: "email_list@test.com"}
	value, err := proto.Marshal(&layout)
	require.NoError(t, err)

	return &anypb.Any{
		TypeUrl: raw.TypeURL,
		Value:   value,
	}
}
