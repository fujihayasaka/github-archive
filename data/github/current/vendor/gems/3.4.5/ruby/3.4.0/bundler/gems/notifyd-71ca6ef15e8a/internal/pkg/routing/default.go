package routing

import (
	"github.com/github/notifyd/internal/pkg/notify"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
)

// ciActivityUserIDCutoff is the user ID cutoff for the CI activity web channel legacy default.
// The web channel was disabled by default until 10th June 2022, after which it became enabled for accounts created after this date.
// See the following issue for more information:
// https://github.com/github/notifyd/issues/4664#issuecomment-2663843867
const ciActivityUserIDCutoff = 107241421

// defaultSettings are the default settings which are applied sequentially
// meaning first element has the lowest priority, last one has the highest
var defaultSettings = []Setting{
	{
		// disable everything by default
		Channels: map[string]*matchengine_dto.Channel{
			"PUSH":  {Channel: "PUSH", Enabled: false},
			"EMAIL": {Channel: "EMAIL", Enabled: false},
		},
	},
	{
		Reason: "mobile_auth_request",
		Channels: map[string]*matchengine_dto.Channel{
			"PUSH": {Channel: "PUSH", Enabled: true},
		},
	},
	{
		Trigger: "pull_request_reviewed",
		Reason:  "pull_request_reviewed",
		Channels: map[string]*matchengine_dto.Channel{
			"PUSH": {Channel: "PUSH", Enabled: true},
		},
	},
	{
		Trigger: "review_requested",
		Reason:  "review_requested",
		Channels: map[string]*matchengine_dto.Channel{
			"PUSH": {Channel: "PUSH", Enabled: true},
		},
	},
	{
		Reason: "mention",
		Channels: map[string]*matchengine_dto.Channel{
			"PUSH": {Channel: "PUSH", Enabled: true},
		},
	},
	{
		Trigger: "assigned",
		Reason:  "assign",
		Channels: map[string]*matchengine_dto.Channel{
			"PUSH": {Channel: "PUSH", Enabled: true},
		},
	},
	{
		Reason: "subscribed",
		Channels: map[string]*matchengine_dto.Channel{
			"EMAIL": {Channel: "EMAIL", Enabled: true},
			"WEB":   {Channel: "WEB", Enabled: true},
		},
	},
	{
		Reason: "approval_requested",
		Channels: map[string]*matchengine_dto.Channel{
			"EMAIL": {Channel: "EMAIL", Enabled: true},
			"PUSH":  {Channel: "PUSH", Enabled: true},
			"WEB":   {Channel: "WEB", Enabled: true},
		},
	},
	{
		Reason: "ci_activity",
		MatchRules: []SettingMatchRule{
			{Attribute: "failed", Value: "false", MatchRule: "eq"},
		},
		Channels: map[string]*matchengine_dto.Channel{
			"EMAIL": {Channel: "EMAIL", Enabled: false},
			"WEB":   {Channel: "WEB", Enabled: false},
		},
	},
	{
		Reason: "ci_activity",
		MatchRules: []SettingMatchRule{
			{Attribute: "failed", Value: "true", MatchRule: "eq"},
		},
		Channels: map[string]*matchengine_dto.Channel{
			"EMAIL": {Channel: "EMAIL", Enabled: true},
			"WEB":   {Channel: "WEB", Enabled: true},
		},
	},
	{
		SubjectType: "GistComment",
		Channels: map[string]*matchengine_dto.Channel{
			"EMAIL": {Channel: "EMAIL", Enabled: true},
			"PUSH":  {Channel: "PUSH", Enabled: false},
		},
	},
	{
		SubjectType: "MemberFeatureRequest::Notification",
		Channels: map[string]*matchengine_dto.Channel{
			"EMAIL": {Channel: "EMAIL", Enabled: true},
			"PUSH":  {Channel: "PUSH", Enabled: false},
			"WEB":   {Channel: "WEB", Enabled: true},
		},
	},
	{
		SubjectType: "MemexProjectStatus",
		Channels: map[string]*matchengine_dto.Channel{
			// make sure we can send web notifications
			"WEB": {Channel: "WEB", Enabled: true},
		},
	},
	{
		SubjectType: "SecurityCampaigns::SecurityCampaignUser",
		Channels: map[string]*matchengine_dto.Channel{
			"EMAIL": {Channel: "EMAIL", Enabled: true},
			"PUSH":  {Channel: "PUSH", Enabled: false},
			"WEB":   {Channel: "WEB", Enabled: false},
		},
	},
}

var recipientSettingsPerFeatureFlag = map[string][]Setting{
	"notifyd_issue_watch_activity_notify": {
		{
			// Enable web and email by default for thread activity for repository watchers, limited to issues
			MatchRules: []SettingMatchRule{
				{Attribute: "watch_activity", Value: "true", MatchRule: "eq"},
				{Attribute: "thread_type", Value: "issue", MatchRule: "eq"},
				{Value: "subscribed", MatchRule: "reason_ne"},
			},
			Channels: map[string]*matchengine_dto.Channel{
				"EMAIL": {Channel: "EMAIL"}, // we take Enabled value from feature flag
				"WEB":   {Channel: "WEB"},   // we take Enabled value from feature flag
			},
		},
		{
			// Enable web and email by default for thread activity for thread participants, limited to issues
			MatchRules: []SettingMatchRule{
				{Attribute: "thread_participant_activity", Value: "true", MatchRule: "eq"},
				{Attribute: "thread_type", Value: "issue", MatchRule: "eq"},
				{Value: "subscribed", MatchRule: "reason_ne"},
			},
			Channels: map[string]*matchengine_dto.Channel{
				"EMAIL": {Channel: "EMAIL"}, // we take Enabled value from feature flag
				"WEB":   {Channel: "WEB"},   // we take Enabled value from feature flag
			},
		},
	},

	// Pull request notifications for email and web should be disabled for now,
	// but we want to start enabling mobile push notifications for pull requests.
	// We cannot do this only with defaults as we need to make sure that these notifications
	// aren't delivered independently of the user subscriptions and settings.
	"notifyd_pull_request_notify_email_and_web": {
		{
			MatchRules: []SettingMatchRule{
				{Attribute: "thread_type", Value: "pull_request", MatchRule: "eq"},
			},
			Channels: map[string]*matchengine_dto.Channel{
				"EMAIL": {Channel: "EMAIL"}, // we take Enabled value from feature flag
				"WEB":   {Channel: "WEB"},   // we take Enabled value from feature flag
			},
		},
	},
}

var dynamicRecipientSettings = map[string][]Setting{
	// Applies legacy default for the web channel for users with ID < ciActivityUserIDCutoff
	"notifyd_ci_activity_legacy_web_default": {
		{
			Reason: "approval_requested",
			Channels: map[string]*matchengine_dto.Channel{
				"WEB": {Channel: "WEB", Enabled: false},
			},
		},
		{
			Reason: "ci_activity",
			MatchRules: []SettingMatchRule{
				{Attribute: "failed", Value: "true", MatchRule: "eq"},
			},
			Channels: map[string]*matchengine_dto.Channel{
				"WEB": {Channel: "WEB", Enabled: false},
			},
		},
	},
}

func applyDefaultSettingsToChannels(matchFields notify.MessageMatchFields, reasons []string, channels matchengine_dto.ChannelsMap) {
	// default settings, currently hardcoded, will be applied only if matchFields and reasons match to default hardcoded settings
	matchAndApplyDefaultSettings(defaultSettings, matchFields, reasons, channels)
}

func applyDefaultDynamicSettingsToChannels(recipientID int64, matchFields notify.MessageMatchFields, reasons []string, channels matchengine_dto.ChannelsMap) {
	if recipientID < ciActivityUserIDCutoff {
		matchAndApplyDefaultSettings(dynamicRecipientSettings["notifyd_ci_activity_legacy_web_default"], matchFields, reasons, channels)
	}
}

func applyDefaultFeatureFlagsSettingsToChannels(featureFlags []featureFlag, matchFields notify.MessageMatchFields, reasons []string, channels matchengine_dto.ChannelsMap) {
	for _, featureFlag := range featureFlags {
		// feature flag settings, will be applied only if matchFields and reasons match to feature flags hardcoded settings
		if featureFlagSettings, ok := recipientSettingsPerFeatureFlag[featureFlag.Name]; ok {
			matchAndApplySettingsWithChannelValue(featureFlagSettings, matchFields, reasons, channels, featureFlag.Enabled)
		}
	}
}

func matchAndApplySettingsWithChannelValue(settings []Setting, matchFields notify.MessageMatchFields, reasons []string, channels matchengine_dto.ChannelsMap, channelEnabled bool) {
	var matched bool
	for _, setting := range settings {
		matched = matchSetting(setting, matchFields, reasons)

		if matched {
			for _, channel := range setting.Channels {
				channels[channel.Channel] = &matchengine_dto.Channel{Channel: channel.Channel, Enabled: channelEnabled}
			}
		}
	}
}

func matchAndApplyDefaultSettings(defaultSettings []Setting, matchFields notify.MessageMatchFields, reasons []string, channels matchengine_dto.ChannelsMap) {
	var matched bool
	for _, setting := range defaultSettings {
		matched = matchSetting(setting, matchFields, reasons)

		if matched {
			for _, channel := range setting.Channels {
				channels[channel.Channel] = &matchengine_dto.Channel{Channel: channel.Channel, Enabled: channel.Enabled}
			}
		}
	}
}

func matchSetting(setting Setting, matchFields notify.MessageMatchFields, reasons []string) bool {
	return (setting.Reason == "" || contains(reasons, setting.Reason)) &&
		(setting.SubjectType == "" || setting.SubjectType == matchFields.SubjectType) &&
		(setting.Trigger == "" || setting.Trigger == matchFields.Trigger) &&
		(len(setting.MatchRules) == 0 || rulesMatch(setting.MatchRules, matchFields.Attributes, reasons))
}

func contains(list []string, value string) bool {
	for _, el := range list {
		if el == value {
			return true
		}
	}
	return false
}

// rulesMatch is true if all the rules in the settings are matched by the attributes, false otherwise.
func rulesMatch(rules []SettingMatchRule, attributes []notify.Attribute, reasons []string) bool {
	for _, rule := range rules {
		if rule.Attribute == "" {
			if !customRuleMatches(rule, reasons) {
				return false
			}
		} else if !ruleMatches(rule, attributes) {
			return false
		}
	}

	return true
}

// ruleMatches is true if a rule is matched by any attribute, false otherwise.
func ruleMatches(rule SettingMatchRule, attributes []notify.Attribute) bool {
	for _, attr := range attributes {
		if attr.Name != rule.Attribute {
			continue
		}
		switch rule.MatchRule {
		case "eq":
			if attr.Value == rule.Value {
				return true
			}
		case "ne":
			if attr.Value != rule.Value {
				return true
			}
		}
	}

	return false
}

func customRuleMatches(rule SettingMatchRule, reasons []string) bool {
	if rule.MatchRule == "reason_ne" {
		if !contains(reasons, rule.Value) {
			return true
		}
	}

	return false
}
