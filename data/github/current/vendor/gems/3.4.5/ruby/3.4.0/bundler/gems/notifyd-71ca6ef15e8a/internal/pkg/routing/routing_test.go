package routing

import (
	"context"
	"fmt"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/github/go-stats"
	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"
	testsuite "github.com/stretchr/testify/suite"

	schema_pb "github.com/github/notifyd/hydro/schemas/notifyd/v0"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/featureflags"
	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/notify/matchengine"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
)

type RoutingServiceTestSuite struct {
	testsuite.Suite
	testhelper.DatabaseSuite
}

func (suite *RoutingServiceTestSuite) TestRoutingService_defaultDeliveryMetadata() {
	db := suite.DB()
	ctx := context.Background()

	setup := func() *storage {
		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_channels",
			"routing_setting_match_rules",
			"routing_setting_custom_fields",
		}
		if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
			panic(fmt.Sprintf("truncate test db: %s", err))
		}
		store := NewStorage(clock.NewMock(), logs.NullTelem, db)
		if storage, ok := store.(*storage); ok {
			return storage
		}
		panic("failed to cast store to *storage")
	}

	tests := []struct {
		name                     string
		notifyMessage            *schema_pb.Notify
		recipients               notify.RecipientIDToReasons
		expectedDeliveryMetadata notify.RecipientToDeliveryMetadata
		featureFlags             map[string][]int64
	}{
		{
			name: "Default routing rules: Allows emails, forbids push notifications for 'subscribed' reasons",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "create",
				},
				Subject: &schema_pb.Notify_Subject{Type: "Issue", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"subscribed"},
				3: []string{"subscribed"},
			},
			expectedDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				2: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}), Reasons: []string{"subscribed"}},
				3: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}), Reasons: []string{"subscribed"}},
			},
		},
		{
			name: "Default routing rules: Allows emails, forbids push notifications for 'approval_requested' reasons",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "create",
				},
				Subject: &schema_pb.Notify_Subject{Type: "Issue", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"approval_requested"},
				3: []string{"approval_requested"},
			},
			expectedDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				2: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}), Reasons: []string{"approval_requested"}},
				3: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}), Reasons: []string{"approval_requested"}},
			},
		},
		{
			name: "Default routing rules: Allows emails, forbids push notifications for failed 'ci_activity' CI Activity",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "completed",
				},
				Attributes: []*schema_pb.Notify_Attribute{
					{Name: "failed", Value: "true"},
				},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "ci_activity", UserIds: []int32{2}},
					{Reason: "ci_activity", UserIds: []int32{3}},
				},
				Subject: &schema_pb.Notify_Subject{Type: "CheckSuite", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"ci_activity"},
				3: []string{"ci_activity"},
			},
			expectedDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				2: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}), Reasons: []string{"ci_activity"}},
				3: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}), Reasons: []string{"ci_activity"}},
			},
		},
		{
			name: "Default routing rules: Forbids emails, forbids push notifications for success 'ci_activity' CI Activity",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "completed",
				},
				Attributes: []*schema_pb.Notify_Attribute{
					{Name: "failed", Value: "false"},
				},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "ci_activity", UserIds: []int32{2}},
					{Reason: "ci_activity", UserIds: []int32{3}},
				},
				Subject: &schema_pb.Notify_Subject{Type: "CheckSuite", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"ci_activity"},
				3: []string{"ci_activity"},
			},
			expectedDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				2: {Channels: testChannel(), Reasons: []string{"ci_activity"}},
				3: {Channels: testChannel(), Reasons: []string{"ci_activity"}},
			},
		},
		{
			name: "Default routing rules: Forbids emails, forbids push notifications for 'ci_activity' without failed attribute",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "completed",
				},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "ci_activity", UserIds: []int32{2}},
					{Reason: "ci_activity", UserIds: []int32{3}},
				},
				Subject: &schema_pb.Notify_Subject{Type: "CheckSuite", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"ci_activity"},
				3: []string{"ci_activity"},
			},
			expectedDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				2: {Channels: testChannel(), Reasons: []string{"ci_activity"}},
				3: {Channels: testChannel(), Reasons: []string{"ci_activity"}},
			},
		},
		{
			name: "Default routing rules: Allows push notifications for reasons 'mention', 'mobile_auth_request' but no 'pull_request_reviewed', 'assign', 'review_requested'",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "create",
				},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2}},
				},
				Subject: &schema_pb.Notify_Subject{Type: "Issue", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention"},
				3: []string{"mobile_auth_request"},
				4: []string{"pull_request_reviewed"},
				5: []string{"assign"},
				6: []string{"review_requested"},
			},
			expectedDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				2: {Channels: testChannel(TestChannel{Channel: "PUSH", Enabled: true}), Reasons: []string{"mention"}},
				3: {Channels: testChannel(TestChannel{Channel: "PUSH", Enabled: true}), Reasons: []string{"mobile_auth_request"}},
				4: {Channels: testChannel(TestChannel{Channel: "PUSH", Enabled: false}), Reasons: []string{"pull_request_reviewed"}},
				5: {Channels: testChannel(TestChannel{Channel: "PUSH", Enabled: false}), Reasons: []string{"assign"}},
				6: {Channels: testChannel(TestChannel{Channel: "PUSH", Enabled: false}), Reasons: []string{"review_requested"}},
			},
		},
		{
			name: "Default routing rules: If there are several reasons, allowlist in delivery metadata adds new channels",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "create",
				},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2}},
					{Reason: "mention", UserIds: []int32{3}},
					{Reason: "2fa", UserIds: []int32{5}},
				},
				Subject: &schema_pb.Notify_Subject{Type: "Issue", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention", "subscribed"},
				4: []string{"subscribed"},
				5: []string{"mention", "2fa"},
			},
			expectedDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				2: {
					Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}, TestChannel{Channel: "PUSH", Enabled: true}),
					Reasons:  []string{"mention", "subscribed"},
				},
				4: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}), Reasons: []string{"subscribed"}},
				5: {Channels: testChannel(TestChannel{Channel: "PUSH", Enabled: true}), Reasons: []string{"mention", "2fa"}},
			},
		},
		{
			name: "Enables PUSH but not EMAIL if user is mentioned and subscribed to thread type but has FF disabled",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "create",
				},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2, 5}},
				},
				Subject: &schema_pb.Notify_Subject{Type: "Issue", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
				Attributes: []*schema_pb.Notify_Attribute{
					{Name: "watch_activity", Value: "true"},
					{Name: "thread_type", Value: "issue"},
					{Name: "thread_id", Value: "456"},
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention", "thread_type_subscription"},
				5: []string{"mention"},
			},
			expectedDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				2: {
					Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}, TestChannel{Channel: "PUSH", Enabled: true}),
					Reasons:  []string{"mention", "thread_type_subscription"},
				},
				5: {Channels: testChannel(TestChannel{Channel: "PUSH", Enabled: true}), Reasons: []string{"mention"}},
			},
		},
		{
			name: "Enables PUSH and EMAIL if user is mentioned and subscribed to thread type and has FF enabled",
			notifyMessage: &schema_pb.Notify{
				Actor:          &schema_pb.Notify_Actor{Id: 1},
				NotificationId: "test-notification-id",
				Context: &schema_pb.Notify_Context{
					Trigger: "create",
				},
				ExplicitRecipients: []*schema_pb.Notify_RecipientGroup{
					{Reason: "mention", UserIds: []int32{2, 5}},
				},
				Subject: &schema_pb.Notify_Subject{Type: "Issue", Value: "1"},
				RelatedTopics: []*schema_pb.Notify_Topic{
					{Type: "repository", Value: "123"},
				},
				Attributes: []*schema_pb.Notify_Attribute{
					{Name: "watch_activity", Value: "true"},
					{Name: "thread_type", Value: "issue"},
					{Name: "thread_id", Value: "456"},
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention", "thread_type_subscription"},
				5: []string{"mention"},
			},
			expectedDeliveryMetadata: map[int64]notify.DeliveryMetadata{
				2: {
					Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}, TestChannel{Channel: "PUSH", Enabled: true}),
					Reasons:  []string{"mention", "thread_type_subscription"},
				},
				5: {Channels: testChannel(TestChannel{Channel: "PUSH", Enabled: true}), Reasons: []string{"mention"}},
			},
			featureFlags: map[string][]int64{
				"notifyd_issue_watch_activity_notify": {2},
			},
		},
	}

	for _, test := range tests {
		suite.Run(test.name, func() {
			storage := setup()

			featuresClient, recipientFeatureFlags := setupFeatureFlagsClientMock(suite.T(), test.featureFlags, test.notifyMessage.Actor.GetId())
			service := NewRoutingService(storage, logs.NullTelem, stats.NullStatter, featuresClient)

			notification := notify.PBToNotification(test.notifyMessage)
			if routingService, ok := service.(routingService); ok {
				actualDeliveryMetadata := routingService.defaultDeliveryMetadata(notification.MessageMatchFields, test.recipients, recipientFeatureFlags)

				for recipientID, expectedDeliveryMetadata := range test.expectedDeliveryMetadata {
					assertChannels(suite.Require(), actualDeliveryMetadata[recipientID].Channels, expectedDeliveryMetadata.Channels)
					suite.Require().Equal(expectedDeliveryMetadata.Reasons, actualDeliveryMetadata[recipientID].Reasons)
				}
			} else {
				suite.T().Error("failed to cast service to routingService")
			}
		})
	}
}

func (suite *RoutingServiceTestSuite) TestRoutingService_GetMatchingRoutingSettingsPerRecipient() {
	ctx := context.Background()
	db := suite.DB()
	t := suite.SequentialIDs()

	setup := func() *storage {
		tables := []string{
			"meta_routing_settings",
			"routing_settings",
			"routing_setting_channels",
			"routing_setting_match_rules",
			"routing_setting_custom_fields",
		}
		if err := testhelper.TruncateTables(ctx, db, tables); err != nil {
			panic(fmt.Sprintf("truncate test db: %s", err))
		}
		store := NewStorage(clock.NewMock(), logs.NullTelem, db)
		if storage, ok := store.(*storage); ok {
			return storage
		}
		panic("failed to cast store to *storage")
	}

	testCases := []struct {
		name                   string
		event                  *MatchQuery
		metaSettings           []*MetaSetting
		recipients             notify.RecipientIDToReasons
		expectedMatchedEntries map[int64][]*matchengine.MatchedEntry
		expectedError          error
		featureFlags           map[string][]int64
	}{
		{
			name: "Doesn't match any routing setting record in database",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "repository", Value: "-1"},
					},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			metaSettings: []*MetaSetting{
				{
					UserID: t.GetRef("1a-user1"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules:  []SettingMatchRule{},
							},
						},
					},
				},
			},
			recipients: notify.RecipientIDToReasons{
				t.GetRef("1a-user1"): []string{"subscribed"},
				t.GetRef("1a-user2"): []string{"subscribed"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{},
			expectedError:          nil,
		},
		{
			name: "Matches routing settings by based on topic",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "repository", Value: "123"},
					},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			metaSettings: []*MetaSetting{
				{
					UserID: t.GetRef("2a-user1"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{},
					},
				},
				{
					UserID: t.GetRef("2a-user2"),
					Name:   "Test sub 2",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
						},
						Filters: []SettingFilter{},
					},
				},
				{
					UserID: t.GetRef("2a-user3"),
					Name:   "Test sub 2",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "repository", Value: "789"},
						},
						Filters: []SettingFilter{},
					},
				},
			},
			recipients: notify.RecipientIDToReasons{
				t.GetRef("2a-user1"): []string{"subscribed"},
				t.GetRef("2a-user2"): []string{"subscribed"},
				t.GetRef("2a-user3"): []string{"subscribed"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{
				t.GetRef("2a-user1"): {{UserID: t.GetRef("2a-user1"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true})}},
				t.GetRef("2a-user2"): {{UserID: t.GetRef("2a-user2"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}},
			},
			expectedError: nil,
		},
		{
			name: "Matches global routing settings by ignoring topic from the message based on reason or subject",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "repository", Value: "123"},
					},
					SubjectType:  "CheckSuite",
					SubjectValue: "1",
					Trigger:      "completed",
				},
			},
			metaSettings: []*MetaSetting{
				{
					UserID: t.GetRef("3a-user1"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
						Topics: []Topic{
							{Type: "any", Value: "any"},
						},
						Filters: []SettingFilter{
							{Reason: "ci_activity"},
						},
					},
				},
				{
					UserID: t.GetRef("3a-user2"),
					Name:   "Test sub 2",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "any", Value: "any"},
						},
						Filters: []SettingFilter{
							{SubjectType: "CheckSuite", Reason: "ci_activity"},
						},
					},
				},
			},
			recipients: notify.RecipientIDToReasons{
				t.GetRef("3a-user1"): []string{"ci_activity"},
				t.GetRef("3a-user2"): []string{"participant"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{
				t.GetRef("3a-user1"): {{UserID: t.GetRef("3a-user1"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true})}},
				t.GetRef("3a-user2"): {{UserID: t.GetRef("3a-user2"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}},
			},
			expectedError: nil,
		},
		{
			name: "Matches routing settings based on topic and subject type",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "repository", Value: "123"},
					},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			metaSettings: []*MetaSetting{
				{
					UserID: t.GetRef("3a-user1"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{SubjectType: "Issue"},
						},
					},
				},
				{
					UserID: t.GetRef("3a-user2"),
					Name:   "Test sub 2",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
						},
						Filters: []SettingFilter{
							{SubjectType: "PullRequest"},
						},
					},
				},
				{
					UserID: t.GetRef("3a-user3"),
					Name:   "Test sub 2",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
						Topics: []Topic{
							{Type: "repository", Value: "789"},
						},
						Filters: []SettingFilter{},
					},
				},
			},
			recipients: notify.RecipientIDToReasons{
				t.GetRef("3a-user1"): []string{"subscribed"},
				t.GetRef("3a-user2"): []string{"subscribed"},
				t.GetRef("3a-user3"): []string{"subscribed"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{
				t.GetRef("3a-user1"): {{UserID: t.GetRef("3a-user1"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true})}},
			},
			expectedError: nil,
		},
		{
			name: "Matches routing settings based on topic and subject type with trigger",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "repository", Value: "123"},
					},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			metaSettings: []*MetaSetting{
				{
					UserID: t.GetRef("4a-user1"),
					Name:   "Test setting 1",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						Filters: []SettingFilter{
							{SubjectType: "Issue"},
						},
					},
				},
				{
					UserID: t.GetRef("4a-user2"),
					Name:   "Test setting 2",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
						},
						Filters: []SettingFilter{
							{SubjectType: "Issue", Trigger: "create"},
						},
					},
				},
				{
					UserID: t.GetRef("4a-user3"),
					Name:   "Test setting 3",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
						},
						Filters: []SettingFilter{
							{SubjectType: "Issue", Trigger: "labeled"},
						},
					},
				},
			},
			recipients: notify.RecipientIDToReasons{
				t.GetRef("4a-user1"): []string{"subscribed"},
				t.GetRef("4a-user2"): []string{"subscribed"},
				t.GetRef("4a-user3"): []string{"subscribed"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{
				t.GetRef("4a-user1"): {{UserID: t.GetRef("4a-user1"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true})}},
				t.GetRef("4a-user2"): {{UserID: t.GetRef("4a-user2"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}},
			},
			expectedError: nil,
		},
		{
			name: "Matches multiple routing settings based on several matching topics",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "repository", Value: "123"},
						{Type: "repository", Value: "456"},
					},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			metaSettings: []*MetaSetting{
				{
					UserID: t.GetRef("5a-user1"),
					Name:   "Test setting 1",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
						},
					},
				},
				{
					UserID: t.GetRef("5a-user2"),
					Name:   "Test setting 2",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "repository", Value: "456"},
						},
					},
				},
				{
					UserID: t.GetRef("5a-user3"),
					Name:   "Test setting 3",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
						Topics: []Topic{
							{Type: "repository", Value: "789"},
						},
					},
				},
			},
			recipients: notify.RecipientIDToReasons{
				t.GetRef("5a-user1"): []string{"subscribed"},
				t.GetRef("5a-user2"): []string{"subscribed"},
				t.GetRef("5a-user3"): []string{"subscribed"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{
				t.GetRef("5a-user1"): {{UserID: t.GetRef("5a-user1"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true})}},
				t.GetRef("5a-user2"): {{UserID: t.GetRef("5a-user2"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}},
			},
			expectedError: nil,
		},
		{
			name: "Matches routing setting by based on topic and in-memory filtering match rules",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "repository", Value: "123"},
					},
					SubjectType:  "CheckSuite",
					SubjectValue: "1",
					Trigger:      "completed",
					Attributes: []notify.Attribute{
						{Name: "conclusion", Value: "failed"},
					},
				},
			},
			metaSettings: []*MetaSetting{
				{
					UserID: t.GetRef("6a-user1"),
					Name:   "Generic repository setting without match rules",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
						},
					},
				},
				{
					UserID: t.GetRef("6a-user2"),
					Name:   "Test setting that matches not all match rules",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
						},
						Filters: []SettingFilter{
							{MatchRules: []SettingMatchRule{
								{Attribute: "conclusion", Value: "failed", MatchRule: "eq"},
								{Attribute: "env", Value: "production", MatchRule: "eq"},
							}},
						},
					},
				},
				{
					UserID: t.GetRef("6a-user3"),
					Name:   "Test setting that does match all match rules",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
						},
						Filters: []SettingFilter{
							{MatchRules: []SettingMatchRule{{Attribute: "conclusion", Value: "failed", MatchRule: "eq"}}},
						},
					},
				},
			},
			recipients: notify.RecipientIDToReasons{
				t.GetRef("6a-user1"): []string{"subscribed"},
				t.GetRef("6a-user2"): []string{"subscribed"},
				t.GetRef("6a-user3"): []string{"subscribed"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{
				t.GetRef("6a-user1"): {{UserID: t.GetRef("6a-user1"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true})}},
				t.GetRef("6a-user3"): {{UserID: t.GetRef("6a-user3"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}},
			},
			expectedError: nil,
		},
		{
			name: "Matches routing setting by based on topic and in-memory `in_reason_group` match rules",
			event: &MatchQuery{
				actorID: 1,
				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "Issue", Value: "321"},
					},
					SubjectType:  "CheckSuite",
					SubjectValue: "1",
					Trigger:      "create",
					Attributes: []notify.Attribute{
						{Name: "thread_participant_activity", Value: "true"},
						{Name: "thread_type", Value: "issue"},
					},
				},
				reasonGroups: []notify.ReasonGroup{
					{Reasons: []string{"mention", "author", "comment"}, Name: "participant"},
				},
			},
			metaSettings: []*MetaSetting{
				{
					UserID: t.GetRef("7a-user1"),
					Name:   "Routing setting 1 that matches in_reason_group match rule",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "issue", Value: "321"},
						},
						Filters: []SettingFilter{
							{MatchRules: []SettingMatchRule{
								{Attribute: "thread_participant_activity", Value: "true", MatchRule: "eq"},
								{Attribute: "", Value: "participant", MatchRule: "in_reason_group"},
							}},
						},
					},
				},
				{
					UserID: t.GetRef("7a-user2"),
					Name:   "Routing setting 2 that matches in_reason_group match rule",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "issue", Value: "321"},
						},
						Filters: []SettingFilter{
							{MatchRules: []SettingMatchRule{
								{Attribute: "thread_participant_activity", Value: "true", MatchRule: "eq"},
								{Attribute: "", Value: "participant", MatchRule: "in_reason_group"},
							}},
						},
					},
				},
				{
					UserID: t.GetRef("7a-user3"),
					Name:   "Test setting that does match all match rules",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "issue", Value: "321"},
						},
						Filters: []SettingFilter{
							{MatchRules: []SettingMatchRule{
								{Attribute: "thread_participant_activity", Value: "true", MatchRule: "eq"},
								{Attribute: "", Value: "participant", MatchRule: "in_reason_group"},
							}},
						},
					},
				},
			},
			recipients: notify.RecipientIDToReasons{
				t.GetRef("7a-user1"): []string{"mention"},
				t.GetRef("7a-user2"): []string{"comment"},
				t.GetRef("7a-user3"): []string{"not_matching_reason"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{
				t.GetRef("7a-user1"): {{UserID: t.GetRef("7a-user1"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}, {UserID: t.GetRef("7a-user1"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}},
				t.GetRef("7a-user2"): {{UserID: t.GetRef("7a-user2"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}, {UserID: t.GetRef("7a-user2"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}},
			},
			expectedError: nil,
		},
		{
			name: "Does not match in_reason_group match rule",
			event: &MatchQuery{
				actorID: 1,

				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "issue", Value: "321"},
					},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
					Attributes: []notify.Attribute{
						{Name: "thread_participant_activity", Value: "true"},
						{Name: "thread_type", Value: "issue"},
					},
				},
				reasonGroups: []notify.ReasonGroup{
					{Reasons: []string{"mention", "author", "comment"}, Name: "participant"},
				},
			},
			metaSettings: []*MetaSetting{
				{
					UserID: t.GetRef("8a-user1"),
					Name:   "Routing setting 1 that matches in_reason_group match rule",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "issue", Value: "321"},
						},
						Filters: []SettingFilter{
							{MatchRules: []SettingMatchRule{
								{Attribute: "thread_participant_activity", Value: "true", MatchRule: "eq"},
								{Attribute: "", Value: "participant", MatchRule: "in_reason_group"},
							}},
						},
					},
				},
			},
			recipients: notify.RecipientIDToReasons{
				t.GetRef("7a-user1"): []string{"author"},
				t.GetRef("7a-user2"): []string{"review_requested"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{},
			expectedError:          nil,
		},
		{
			name: "Matches based on not_in_reason_group match rule",
			event: &MatchQuery{
				actorID: 1,

				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "issue", Value: "321"},
					},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
					Attributes: []notify.Attribute{
						{Name: "thread_participant_activity", Value: "true"},
						{Name: "thread_type", Value: "issue"},
					},
				},
				reasonGroups: []notify.ReasonGroup{
					{Reasons: []string{"self-mention", "author"}, Name: "myself"},
				},
			},
			metaSettings: []*MetaSetting{
				{
					UserID: t.GetRef("9a-user1"),
					Name:   "Routing setting for disabling self-mentions and authors",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "issue", Value: "321"},
						},
						Filters: []SettingFilter{
							{MatchRules: []SettingMatchRule{
								{MatchRule: "eq", Attribute: "thread_participant_activity", Value: "true"},
								{MatchRule: "not_in_reason_group", Value: "myself"},
							}},
						},
					},
				},
			},
			recipients: notify.RecipientIDToReasons{
				t.GetRef("9a-user1"): []string{"review_requested"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{
				t.GetRef("9a-user1"): {{UserID: t.GetRef("9a-user1"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}, {UserID: t.GetRef("9a-user1"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}},
			},
			expectedError: nil,
		},
		{
			name: "Matches intersection between potential recipients and topics",
			event: &MatchQuery{
				actorID: 1,
				reasonGroups: []notify.ReasonGroup{
					{Reasons: []string{"self-mention", "author"}, Name: "myself"},
				},
				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "repository", Value: "123"},
					},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			metaSettings: []*MetaSetting{
				{
					UserID: t.GetRef("7a-user1"),
					Name:   "Test sub 1",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
						},
						Filters: []SettingFilter{},
					},
				},
				{
					UserID: t.GetRef("7a-user2"),
					Name:   "Test sub 2",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
						},
						Filters: []SettingFilter{},
					},
				},
				{
					UserID: t.GetRef("7a-user3"),
					Name:   "Test sub 2",
					Details: SettingDetails{
						Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
						Topics: []Topic{
							{Type: "repository", Value: "123"},
						},
						Filters: []SettingFilter{},
					},
				},
			},
			recipients: notify.RecipientIDToReasons{
				t.GetRef("7a-user1"): []string{"subscribed"},
				t.GetRef("7a-user2"): []string{"subscribed"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{
				t.GetRef("7a-user1"): {{UserID: t.GetRef("7a-user1"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true})}},
				t.GetRef("7a-user2"): {{UserID: t.GetRef("7a-user2"), Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false})}},
			},
			expectedError: nil,
		},
		{
			name: "Returns error when Notify message is invalid",
			event: &MatchQuery{
				actorID: 1,
				reasonGroups: []notify.ReasonGroup{
					{Reasons: []string{"self-mention", "author"}, Name: "myself"},
				},
				fields: notify.MessageMatchFields{
					Topics:       []notify.Topic{},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"subscribed"},
				3: []string{"subscribed"},
			},
			expectedMatchedEntries: map[int64][]*matchengine.MatchedEntry{},
			expectedError:          notify.ErrNoRelatedTopics,
		},
	}
	for _, test := range testCases {
		suite.Run(test.name, func() {
			storage := setup()

			featuresClient, _ := setupFeatureFlagsClientMock(suite.T(), test.featureFlags, int32(test.event.actorID))
			service := NewRoutingService(storage, logs.NullTelem, stats.NullStatter, featuresClient)

			for _, s := range test.metaSettings {
				_, err := storage.Create(ctx, s)
				suite.Require().NoError(err)
			}

			recipientIDToMatchedEntry, err := service.(routingService).getMatchingSettingsPerRecipients(ctx, test.recipients, test.event)

			if test.expectedError != nil {
				suite.Require().Error(err)
				return
			}

			suite.Require().NoError(err)

			suite.Require().Len(recipientIDToMatchedEntry, len(test.expectedMatchedEntries))

			for recipientID, expectedMatchedEntries := range test.expectedMatchedEntries {
				actualMatchEntries := recipientIDToMatchedEntry[recipientID]

				suite.Require().Equal(len(actualMatchEntries), len(expectedMatchedEntries))
				for idx, expectedEntry := range expectedMatchedEntries {
					assertChannels(suite.Require(), actualMatchEntries[idx].Channels, expectedEntry.Channels)
					suite.Require().Equal(expectedEntry.UserID, actualMatchEntries[idx].UserID)
				}
			}
		})
	}
}

func TestRoutingService_GetDeliveryMetadata(t *testing.T) {
	ctx := context.Background()

	setup := func() *StorageMock {
		routingDBstorageMock := new(StorageMock)
		return routingDBstorageMock
	}

	validEvent := &MatchQuery{
		actorID:      1,
		reasonGroups: []notify.ReasonGroup{},
		fields: notify.MessageMatchFields{
			Topics: []notify.Topic{
				{Type: "repository", Value: "123"},
			},
			SubjectType:  "Issue",
			SubjectValue: "1",
			Trigger:      "create",
		},
	}

	testCases := []struct {
		name                     string
		event                    *MatchQuery
		matchingEntries          []*matchengine.MatchedEntry
		matchedChannels          map[int64][]matchengine_dto.Channel
		getMatchingEntriesError  error
		recipients               notify.RecipientIDToReasons
		expectedDeliveryMetadata notify.RecipientToDeliveryMetadata
		featureFlags             map[string][]int64
	}{
		{
			name: "Should return default routing settings if provided invalid message",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics:       []notify.Topic{},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			matchedChannels: map[int64][]matchengine_dto.Channel{},
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention"},
			},
			getMatchingEntriesError: errors.New("test error"),
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {Channels: testChannel(TestChannel{Channel: "PUSH", Enabled: true}), Reasons: []string{"mention"}},
			},
			featureFlags: map[string][]int64{
				"notifyd_issue_watch_activity_notify": {2},
			},
		},
		{
			name: "Should return default routing settings if use_default_routing enabled",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics:       []notify.Topic{},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			matchedChannels: map[int64][]matchengine_dto.Channel{},
			recipients: notify.RecipientIDToReasons{
				2: []string{"mobile_auth_request"},
			},
			getMatchingEntriesError: errors.New("test error"),
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {Channels: testChannel(TestChannel{Channel: "PUSH", Enabled: true}), Reasons: []string{"mobile_auth_request"}},
			},
			featureFlags: map[string][]int64{
				"notifyd_issue_watch_activity_notify": {2},
			},
		},
		{
			name: "Should return default routing settings if provided invalid message and FF notifyd_issue_watch_activity_notify is enabled",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics:       []notify.Topic{},
					SubjectType:  "Issue",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			matchedChannels: map[int64][]matchengine_dto.Channel{},
			recipients: notify.RecipientIDToReasons{
				2: []string{"subscribed"},
				3: []string{"thread_type_subscription"},
			},
			getMatchingEntriesError: errors.New("test error"),
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}), Reasons: []string{"subscribed"}},
				3: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}), Reasons: []string{"thread_type_subscription"}},
			},
			featureFlags: map[string][]int64{
				"notifyd_issue_watch_activity_notify": {3},
			},
		},
		{
			name:  "Should return default routing settings if unable to fetch matched routing settings",
			event: validEvent,
			recipients: notify.RecipientIDToReasons{
				2: []string{"subscribed"},
				3: []string{"subscribed"},
			},
			getMatchingEntriesError: errors.New("test error"),
			matchedChannels:         map[int64][]matchengine_dto.Channel{},
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}), Reasons: []string{"subscribed"}},
				3: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}), Reasons: []string{"subscribed"}},
			},
		},
		{
			name:  "Should disable channels (only EMAIL for now) if found Notify=false matched setting",
			event: validEvent,
			recipients: notify.RecipientIDToReasons{
				2: []string{"subscribed"},
				3: []string{"subscribed"},
			},
			matchingEntries: []*matchengine.MatchedEntry{
				{RefID: 1, UserID: 2},
				{RefID: 2, UserID: 2},
				{RefID: 3, UserID: 3},
			},
			matchedChannels: map[int64][]matchengine_dto.Channel{
				1: {{Channel: "EMAIL", Enabled: true, RoutingSettingID: 1}},
				2: {{Channel: "EMAIL", Enabled: false, RoutingSettingID: 2}},
				3: {{Channel: "EMAIL", Enabled: false, RoutingSettingID: 3}},
			},
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}), Reasons: []string{"subscribed"}},
				3: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}), Reasons: []string{"subscribed"}},
			},
		},
		{
			name:  "Should enable channels (only EMAIL for now) if found notify true matched setting",
			event: validEvent,
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention"},
				3: []string{"subscribed"},
			},
			matchingEntries: []*matchengine.MatchedEntry{
				{RefID: 1, UserID: 2},
				{RefID: 2, UserID: 3},
			},
			matchedChannels: map[int64][]matchengine_dto.Channel{
				1: {{Channel: "EMAIL", Enabled: true, RoutingSettingID: 1}},
				2: {{Channel: "EMAIL", Enabled: true, RoutingSettingID: 2}},
			},
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {
					Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}, TestChannel{Channel: "PUSH", Enabled: true}),
					Reasons:  []string{"mention"},
				},
				3: {
					Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}),
					Reasons:  []string{"subscribed"},
				},
			},
		},
		{
			name:  "Should merge default routing settings with stored settings",
			event: validEvent,
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention", "subscribed"},
				3: []string{"subscribed"},
			},
			matchingEntries: []*matchengine.MatchedEntry{
				{RefID: 1, UserID: 2},
				{RefID: 2, UserID: 3},
			},
			matchedChannels: map[int64][]matchengine_dto.Channel{
				1: {{Channel: "EMAIL", Enabled: false, RoutingSettingID: 1}},
				2: {{Channel: "EMAIL", Enabled: false, RoutingSettingID: 2}},
			},
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {
					Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}, TestChannel{Channel: "PUSH", Enabled: true}),
					Reasons:  []string{"mention", "subscribed"},
				},
				3: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}), Reasons: []string{"subscribed"}},
			},
		},
		{
			name:  "Default routing settings and stored settings with channel ALL to true",
			event: validEvent,
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention", "subscribed"},
				3: []string{"subscribed"},
			},
			matchingEntries: []*matchengine.MatchedEntry{
				{RefID: 1, UserID: 2},
				{RefID: 2, UserID: 3},
			},
			matchedChannels: map[int64][]matchengine_dto.Channel{
				1: {{Channel: "ALL", Enabled: true, RoutingSettingID: 1}},
				2: {{Channel: "ALL", Enabled: true, RoutingSettingID: 2}},
			},
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {
					Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}, TestChannel{Channel: "PUSH", Enabled: true}),
					Reasons:  []string{"mention", "subscribed"},
				},
				3: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}), Reasons: []string{"subscribed"}},
			},
		},
		{
			name:  "Default routing settings and stored settings with channel ALL to false",
			event: validEvent,
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention", "subscribed"},
				3: []string{"subscribed"},
			},
			matchingEntries: []*matchengine.MatchedEntry{
				{RefID: 1, UserID: 2},
				{RefID: 2, UserID: 3},
			},
			matchedChannels: map[int64][]matchengine_dto.Channel{
				1: {{Channel: "ALL", Enabled: false, RoutingSettingID: 1}},
				2: {{Channel: "ALL", Enabled: false, RoutingSettingID: 2}},
			},
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {
					Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}, TestChannel{Channel: "PUSH", Enabled: false}),
					Reasons:  []string{"mention", "subscribed"},
				},
				3: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}), Reasons: []string{"subscribed"}},
			},
		},
		{
			name:  "ALL channel overrides default and stored routing settings",
			event: validEvent,
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention", "subscribed"},
				3: []string{"subscribed"},
			},
			matchingEntries: []*matchengine.MatchedEntry{
				{RefID: 1, UserID: 2},
				{RefID: 2, UserID: 3},
				{RefID: 3, UserID: 2},
				{RefID: 4, UserID: 3},
			},
			matchedChannels: map[int64][]matchengine_dto.Channel{
				1: {{Channel: "ALL", Enabled: true, RoutingSettingID: 1}},
				2: {{Channel: "ALL", Enabled: false, RoutingSettingID: 2}},
				3: {{Channel: "EMAIL", Enabled: false, RoutingSettingID: 1}},
				4: {{Channel: "EMAIL", Enabled: true, RoutingSettingID: 2}},
			},
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {
					Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}, TestChannel{Channel: "PUSH", Enabled: true}),
					Reasons:  []string{"mention", "subscribed"},
				},
				3: {Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}), Reasons: []string{"subscribed"}},
			},
		},
		{
			name: "Does not apply stored routing settings if reasons do not match",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "gist", Value: "123"},
					},
					SubjectType:  "GistComment",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention"},
			},
			matchingEntries: []*matchengine.MatchedEntry{
				{RefID: 1, UserID: 2, Reason: "comment"},
				{RefID: 2, UserID: 2, Reason: "author"},
				{RefID: 3, UserID: 2, Reason: "manual"},
			},
			matchedChannels: map[int64][]matchengine_dto.Channel{
				1: {{Channel: "ALL", Enabled: false, RoutingSettingID: 1}},
				2: {{Channel: "ALL", Enabled: false, RoutingSettingID: 2}},
				3: {{Channel: "ALL", Enabled: false, RoutingSettingID: 3}},
			},
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {
					Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: true}, TestChannel{Channel: "PUSH", Enabled: false}),
					Reasons:  []string{"mention"},
				},
			},
		},
		{
			name: "Apply stored routing settings if reasons match",
			event: &MatchQuery{
				actorID:      1,
				reasonGroups: []notify.ReasonGroup{},
				fields: notify.MessageMatchFields{
					Topics: []notify.Topic{
						{Type: "gist", Value: "123"},
					},
					SubjectType:  "GistComment",
					SubjectValue: "1",
					Trigger:      "create",
				},
			},
			recipients: notify.RecipientIDToReasons{
				2: []string{"mention", "comment"},
			},
			matchingEntries: []*matchengine.MatchedEntry{
				{RefID: 1, UserID: 2, Reason: "comment"},
				{RefID: 2, UserID: 2, Reason: "author"},
				{RefID: 3, UserID: 2, Reason: "manual"},
			},
			matchedChannels: map[int64][]matchengine_dto.Channel{
				1: {{Channel: "ALL", Enabled: false, RoutingSettingID: 1}},
				2: {{Channel: "ALL", Enabled: false, RoutingSettingID: 2}},
				3: {{Channel: "ALL", Enabled: false, RoutingSettingID: 3}},
			},
			expectedDeliveryMetadata: notify.RecipientToDeliveryMetadata{
				2: {
					Channels: testChannel(TestChannel{Channel: "EMAIL", Enabled: false}, TestChannel{Channel: "PUSH", Enabled: false}),
					Reasons:  []string{"mention", "comment"},
				},
			},
		},
	}

	for _, test := range testCases {
		t.Run(test.name, func(t *testing.T) {
			storageMock := setup()

			featuresClient, _ := setupFeatureFlagsClientMock(t, test.featureFlags, int32(test.event.actorID))
			service := NewRoutingService(storageMock, logs.NullTelem, stats.NullStatter, featuresClient)

			if test.getMatchingEntriesError != nil {
				storageMock.On("GetMatchingEntries", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil, test.getMatchingEntriesError)
			} else {
				storageMock.On("GetMatchingEntries", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(test.matchingEntries, nil)
			}

			storageMock.On("GetChannels", mock.Anything, mock.Anything).Return(test.matchedChannels, nil)

			recipientsDeliveryMetadata := service.GetDeliveryMetadata(ctx, test.recipients, test.event)
			require.Len(t, recipientsDeliveryMetadata, len(test.expectedDeliveryMetadata))

			for recipientID, expectedDeliveryMetadata := range test.expectedDeliveryMetadata {
				assertChannels(require.New(t), recipientsDeliveryMetadata[recipientID].Channels, expectedDeliveryMetadata.Channels)
				require.Equal(t, expectedDeliveryMetadata.Reasons, recipientsDeliveryMetadata[recipientID].Reasons)
			}
		})
	}
}

func TestRoutingSettingsTestSuiteGetMatchingEntries(t *testing.T) {
	testsuite.Run(t, new(RoutingServiceTestSuite))
}

func setupFeatureFlagsClientMock(t *testing.T, flags map[string][]int64, _ int32) (featureflags.Client, map[int64][]featureFlag) {
	t.Helper()

	featuresClient := new(featureflags.ClientMock)
	recipientFeatureFlags := make(map[int64][]featureFlag)

	for flag := range recipientSettingsPerFeatureFlag {
		enabledRecipients := make(map[string]bool)

		if recipientIDs, ok := flags[flag]; ok {
			for _, recipientID := range recipientIDs {
				enabledRecipients[fmt.Sprintf("User:%d", recipientID)] = true

				if _, ok := recipientFeatureFlags[recipientID]; !ok {
					recipientFeatureFlags[recipientID] = []featureFlag{}
				}

				recipientFeatureFlags[recipientID] = append(recipientFeatureFlags[recipientID], featureFlag{Name: flag, Enabled: true})
			}
		}

		featuresClient.On("IsEnabledForActors", mock.Anything, flag, mock.Anything).Return(enabledRecipients, nil)
	}

	return featuresClient, recipientFeatureFlags
}
