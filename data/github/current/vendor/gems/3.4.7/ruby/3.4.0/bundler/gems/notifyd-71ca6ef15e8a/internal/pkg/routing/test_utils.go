package routing

import (
	"sort"

	"github.com/stretchr/testify/require"

	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
)

// AssertMetaSettingIsSaved asserts that a slice of meta sesttings are saved as expected
func AssertMetaSettingIsSaved(r *require.Assertions, expectedSetting, savedSetting *MetaSetting) {
	r.Equal(expectedSetting.UserID, savedSetting.UserID)
	r.Len(expectedSetting.Details.Filters, len(savedSetting.Details.Filters))

	// assert filters
	for filterIdx := range expectedSetting.Details.Filters {
		expectedFilter := expectedSetting.Details.Filters[filterIdx]
		savedFilter := savedSetting.Details.Filters[filterIdx]

		r.Equal(expectedFilter.Trigger, savedFilter.Trigger)
		r.Equal(expectedFilter.SubjectType, savedFilter.SubjectType)
		r.Equal(expectedFilter.Reason, savedFilter.Reason)

		// assert match rules
		r.Len(expectedFilter.MatchRules, len(savedFilter.MatchRules))

		for ruleIdx := range expectedFilter.MatchRules {
			r.Equal(expectedFilter.MatchRules[ruleIdx].Attribute, savedFilter.MatchRules[ruleIdx].Attribute)
			r.Equal(expectedFilter.MatchRules[ruleIdx].Value, savedFilter.MatchRules[ruleIdx].Value)
			r.Equal(expectedFilter.MatchRules[ruleIdx].MatchRule, savedFilter.MatchRules[ruleIdx].MatchRule)
		}
	}

	r.Len(expectedSetting.Details.Topics, len(savedSetting.Details.Topics))

	// assert topics
	for topicIdx := range expectedSetting.Details.Topics {
		r.Equal(expectedSetting.Details.Topics[topicIdx].Type, savedSetting.Details.Topics[topicIdx].Type)
		r.Equal(expectedSetting.Details.Topics[topicIdx].Value, savedSetting.Details.Topics[topicIdx].Value)
	}

	// assert custom fields
	r.Len(expectedSetting.Details.CustomFields, len(savedSetting.Details.CustomFields))

	// assert custom fields
	for customFieldIdx := range expectedSetting.Details.CustomFields {
		r.Equal(expectedSetting.Details.CustomFields[customFieldIdx].Name, savedSetting.Details.CustomFields[customFieldIdx].Name)
		r.Equal(expectedSetting.Details.CustomFields[customFieldIdx].Value, savedSetting.Details.CustomFields[customFieldIdx].Value)
	}

	// assert channels
	for name := range expectedSetting.Details.Channels {
		r.Equal(expectedSetting.Details.Channels[name].Channel, savedSetting.Details.Channels[name].Channel)
		r.Equal(expectedSetting.Details.Channels[name].Enabled, savedSetting.Details.Channels[name].Enabled)
	}
}

// AssertSettingsAreSaved aserts that a slice of settings are saved as expected
func AssertSettingsAreSaved(r *require.Assertions, expectedSettings, savedSettings []*Setting) {
	r.Len(savedSettings, len(expectedSettings))

	sort.Slice(savedSettings, func(i, j int) bool {
		return savedSettings[i].ID < savedSettings[j].ID
	})

	for idx, expected := range expectedSettings {
		r.Equal(expected.UserID, savedSettings[idx].UserID)
		r.Equal(expected.TopicType, savedSettings[idx].TopicType)
		r.Equal(expected.TopicValue, savedSettings[idx].TopicValue)
		r.Equal(expected.SubjectType, savedSettings[idx].SubjectType)
		r.Equal(expected.Trigger, savedSettings[idx].Trigger)

		assertChannels(r, savedSettings[idx].Channels, expected.Channels)

		r.Len(expected.MatchRules, len(savedSettings[idx].MatchRules))
		for ruleIdx := range expected.MatchRules {
			expectedRule := expected.MatchRules[ruleIdx]
			rule := savedSettings[idx].MatchRules[ruleIdx]
			r.Equal(expectedRule.Attribute, rule.Attribute)
			r.Equal(expectedRule.Value, rule.Value)
			r.Equal(expectedRule.MatchRule, rule.MatchRule)
		}
	}
}

// TestChannel is a helper struct to build how the result of tests should look like.
type TestChannel struct {
	Channel string
	Enabled bool
}

func testChannel(testRecords ...TestChannel) matchengine_dto.ChannelsMap {
	var resultMap = make(map[string]*matchengine_dto.Channel)
	for _, r := range testRecords {
		resultMap[r.Channel] = &matchengine_dto.Channel{
			Channel: r.Channel,
			Enabled: r.Enabled,
		}
	}

	return resultMap
}

// ToChannelsMap transform a map with channel - enabled key pars into a ChannelMap structure
func ToChannelsMap(simpleMap map[string]bool) matchengine_dto.ChannelsMap {
	var resultMap = make(matchengine_dto.ChannelsMap)

	for name, boolValue := range simpleMap {
		resultMap[name] = &matchengine_dto.Channel{
			Channel: name,
			Enabled: boolValue,
		}
	}

	return resultMap
}

func assertChannels(r *require.Assertions, actualChannels, expectedChannels matchengine_dto.ChannelsMap) {
	for name, expectedChannel := range expectedChannels {
		channel, exists := actualChannels[name]

		r.True(exists)
		r.Equal(expectedChannel.Channel, channel.Channel)
		r.Equal(expectedChannel.Enabled, channel.Enabled, "Channel "+expectedChannel.Channel+" is not equal")

		if expectedChannel.RoutingSettingID != 0 {
			r.Equal(expectedChannel.RoutingSettingID, channel.RoutingSettingID)
		}
	}
}
