package routing

import (
	"testing"

	testsuite "github.com/stretchr/testify/suite"

	"github.com/github/notifyd/internal/pkg/notify"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
)

type SettingsDefaultTestSuite struct {
	testsuite.Suite
}

func TestSettingsDefaultTestSuite(t *testing.T) {
	testsuite.Run(t, new(SettingsDefaultTestSuite))
}

func (suite *SettingsDefaultTestSuite) TestDefaultSettings_applyDefaultSettingsToChannels() {
	testCases := []struct {
		name             string
		matchFields      notify.MessageMatchFields
		reasons          []string
		expectedChannels matchengine_dto.ChannelsMap
	}{
		{
			name:    "ci_activity successful run: notifications are disabled",
			reasons: []string{"ci_activity"},
			matchFields: notify.MessageMatchFields{
				Attributes: []notify.Attribute{
					{Name: "failed", Value: "false"},
				},
			},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: false},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: false},
			},
		},
		{
			name: "ci_activity failed run: email notifications are enabled",
			matchFields: notify.MessageMatchFields{
				Attributes: []notify.Attribute{
					{Name: "failed", Value: "true"},
				},
			},
			reasons: []string{"ci_activity"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
		},
		{
			name:    "reason 'subscribed': emails and web are enabled",
			reasons: []string{"subscribed"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
		},
		{
			name:    "reason 'review_requested': push enabled, emails disabled (handled by newsies for now)",
			reasons: []string{"review_requested"},
			matchFields: notify.MessageMatchFields{
				Trigger: "review_requested",
			},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: false},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: true},
			},
		},
		{
			name:    "reason 'approval_requested': emails are enabled",
			reasons: []string{"approval_requested"},
			matchFields: notify.MessageMatchFields{
				Trigger: "approval_requested",
			},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: true},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
		},
		{
			name:    "reason 'assign': push enabled, emails disabled (handled by newsies for now)",
			reasons: []string{"assign"},
			matchFields: notify.MessageMatchFields{
				Trigger: "assigned",
			},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: false},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: true},
			},
		},
		{
			name: "Subject GistComment: emails are enabled",
			matchFields: notify.MessageMatchFields{
				SubjectType: "GistComment",
			},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
			},
		},
		{
			name: "Subject MemberFeatureRequest::Notification are enabled",
			matchFields: notify.MessageMatchFields{
				SubjectType: "MemberFeatureRequest::Notification",
			},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
		},
		{
			name:    "reason 'mention': pushes are enabled",
			reasons: []string{"mention"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: false},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: true},
			},
		},
		{
			name:    "reasons 'mention' and 'subscribed': pushes, emails, and web are enabled",
			reasons: []string{"mention", "subscribed"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: true},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
		},
		{
			name: "Subject MemexProjectStatus are enabled",
			matchFields: notify.MessageMatchFields{
				SubjectType: "MemexProjectStatus",
			},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: false},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
		},
		{
			name: "Subject SecurityCampaigns::SecurityCampaignUser are enabled",
			matchFields: notify.MessageMatchFields{
				SubjectType: "SecurityCampaigns::SecurityCampaignUser",
			},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: false},
			},
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			channels := make(matchengine_dto.ChannelsMap)
			applyDefaultSettingsToChannels(test.matchFields, test.reasons, channels)

			suite.Require().Equal(test.expectedChannels, channels)
		})
	}
}

func (suite *SettingsDefaultTestSuite) TestDefaultSettings_ApplyFeatureFlagsSettingsToChannels() {
	testCases := []struct {
		name             string
		matchFields      notify.MessageMatchFields
		reasons          []string
		featureFlags     []featureFlag
		expectedChannels matchengine_dto.ChannelsMap
	}{
		{
			name:    "reason 'subscribed': emails are enabled when notifyd_issue_watch_activity_notify FF is disabled",
			reasons: []string{"subscribed"},
			matchFields: notify.MessageMatchFields{
				SubjectType: "IssueComment",
				Attributes: []notify.Attribute{
					{Name: "watch_activity", Value: "true"},
					{Name: "thread_type", Value: "issue"},
					{Name: "thread_id", Value: "456"},
				},
			},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
			featureFlags: []featureFlag{{Name: "notifyd_issue_watch_activity_notify", Enabled: false}},
		},
		{
			name: "Subject GistComment: emails are enabled when notifyd_issue_watch_activity_notify FF is disabled",
			matchFields: notify.MessageMatchFields{
				SubjectType: "GistComment",
			},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
			},
		},
		{
			name:    "reason 'mention': pushes are enabled when notifyd_issue_watch_activity_notify FF is disabled",
			reasons: []string{"mention"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: true},
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: false},
			},
		},
		{
			name:    "reasons 'mention' and 'subscribed': pushes and emails are enabled when notifyd_issue_watch_activity_notify FF is disabled",
			reasons: []string{"mention", "subscribed"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: true},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
		},
		{
			name: "reason 'thread_type_subscription': pushes and emails are disabled when notifyd_issue_watch_activity_notify FF is disabled",
			matchFields: notify.MessageMatchFields{
				SubjectType: "IssueComment",
				Attributes: []notify.Attribute{
					{Name: "watch_activity", Value: "true"},
					{Name: "thread_type", Value: "issue"},
					{Name: "thread_id", Value: "456"},
				},
			},
			reasons: []string{"thread_type_subscription"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: false},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
			},
		},
		{
			name:    "reason 'thread_type_subscription': emails are enabled when notifyd_issue_watch_activity_notify FF is enabled",
			reasons: []string{"thread_type_subscription"},
			matchFields: notify.MessageMatchFields{
				SubjectType: "IssueComment",
				Attributes: []notify.Attribute{
					{Name: "watch_activity", Value: "true"},
					{Name: "thread_type", Value: "issue"},
					{Name: "thread_id", Value: "456"},
				},
			},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
			featureFlags: []featureFlag{{Name: "notifyd_issue_watch_activity_notify", Enabled: true}},
		},
		{
			name: "pushes and emails are disabled for thread participants when notifyd_issue_watch_activity_notify FF is disabled",
			matchFields: notify.MessageMatchFields{
				SubjectType: "IssueComment",
				Attributes: []notify.Attribute{
					{Name: "thread_participant_activity", Value: "true"},
					{Name: "thread_type", Value: "issue"},
					{Name: "thread_id", Value: "456"},
				},
			},
			reasons: []string{"author"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: false},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
			},
		},
		{
			name: "emails are enabled for thread participants when notifyd_issue_watch_activity_notify FF is enabled",
			matchFields: notify.MessageMatchFields{
				SubjectType: "IssueComment",
				Attributes: []notify.Attribute{
					{Name: "thread_participant_activity", Value: "true"},
					{Name: "thread_type", Value: "issue"},
					{Name: "thread_id", Value: "456"},
				},
			},
			reasons: []string{"author"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
			featureFlags: []featureFlag{{Name: "notifyd_issue_watch_activity_notify", Enabled: true}},
		},
		{
			name: "emails are disabled for thread participants when notifyd_issue_watch_activity_notify FF is disabled",
			matchFields: notify.MessageMatchFields{
				SubjectType: "IssueComment",
				Attributes: []notify.Attribute{
					{Name: "thread_participant_activity", Value: "true"},
					{Name: "thread_type", Value: "issue"},
					{Name: "thread_id", Value: "456"},
				},
			},
			reasons: []string{"author"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: false},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: false},
			},
			featureFlags: []featureFlag{{Name: "notifyd_issue_watch_activity_notify", Enabled: false}},
		},
		{
			name: "pull requests are enabled for push only with FF disabled",
			matchFields: notify.MessageMatchFields{
				SubjectType: "IssueComment",
				Attributes: []notify.Attribute{
					{Name: "thread_participant_activity", Value: "true"},
					{Name: "thread_type", Value: "pull_request"},
					{Name: "thread_id", Value: "456"},
				},
			},
			reasons: []string{"mention"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: false},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: true},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: false},
			},
			featureFlags: []featureFlag{
				{Name: "notifyd_pull_request_notify_email_and_web", Enabled: false},
			},
		},
		{
			name: "pull requests are enabled in all channels with FF enabled",
			matchFields: notify.MessageMatchFields{
				SubjectType: "IssueComment",
				Attributes: []notify.Attribute{
					{Name: "thread_participant_activity", Value: "true"},
					{Name: "thread_type", Value: "pull_request"},
					{Name: "thread_id", Value: "456"},
				},
			},
			reasons: []string{"mention"},
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: true},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
			featureFlags: []featureFlag{
				{Name: "notifyd_pull_request_notify_email_and_web", Enabled: true},
			},
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			channels := make(matchengine_dto.ChannelsMap)
			applyDefaultSettingsToChannels(test.matchFields, test.reasons, channels)
			applyDefaultFeatureFlagsSettingsToChannels(test.featureFlags, test.matchFields, test.reasons, channels)

			suite.Require().Equal(test.expectedChannels, channels)
		})
	}
}

func (suite *SettingsDefaultTestSuite) TestDefaultSettings_ApplyDefaultDynamicSettingsToChannels() {
	testCases := []struct {
		name             string
		matchFields      notify.MessageMatchFields
		reasons          []string
		recipientID      int64
		expectedChannels matchengine_dto.ChannelsMap
	}{
		{
			name:    "ci_activity where user ID is non-legacy: web channel is enabled",
			reasons: []string{"ci_activity"},
			matchFields: notify.MessageMatchFields{
				Attributes: []notify.Attribute{
					{Name: "failed", Value: "true"},
				},
			},
			recipientID: ciActivityUserIDCutoff,
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
		},
		{
			name:    "ci_activity where user ID is legacy: web channel is disabled",
			reasons: []string{"ci_activity"},
			matchFields: notify.MessageMatchFields{
				Attributes: []notify.Attribute{
					{Name: "failed", Value: "true"},
				},
			},
			recipientID: ciActivityUserIDCutoff - 1,
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: false},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: false},
			},
		},
		{
			name:        "approval_requested where user ID is non-legacy: web channel is enabled",
			reasons:     []string{"approval_requested"},
			recipientID: ciActivityUserIDCutoff,
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: true},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: true},
			},
		},
		{
			name:        "approval_requested where user ID is legacy: web channel is disabled",
			reasons:     []string{"approval_requested"},
			recipientID: ciActivityUserIDCutoff - 1,
			expectedChannels: matchengine_dto.ChannelsMap{
				"EMAIL": &matchengine_dto.Channel{Channel: "EMAIL", Enabled: true},
				"PUSH":  &matchengine_dto.Channel{Channel: "PUSH", Enabled: true},
				"WEB":   &matchengine_dto.Channel{Channel: "WEB", Enabled: false},
			},
		},
	}

	for _, test := range testCases {
		suite.Run(test.name, func() {
			channels := make(matchengine_dto.ChannelsMap)
			applyDefaultSettingsToChannels(test.matchFields, test.reasons, channels)
			applyDefaultDynamicSettingsToChannels(test.recipientID, test.matchFields, test.reasons, channels)

			suite.Require().Equal(test.expectedChannels, channels)
		})
	}
}
