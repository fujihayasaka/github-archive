package newsiesservice

import (
	"testing"

	matchengine "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"

	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/routing"
)

func Test_listSettingsBuilder(t *testing.T) {
	r := require.New(t)
	builder := ignoreBuilder{
		refType: "repository",
		refID:   1,
	}

	r.Equal("Ignore", builder.Title())
	r.Equal("all", builder.Category())
	r.Equal("any", builder.Reason())
	r.Equal("ALL", builder.Channels()["ALL"].Channel)
	r.False(builder.Channels()["ALL"].Enabled)

	fields := builder.CustomFields([]routing.CustomField{
		{Name: OwnerIDName, Value: "123"},
		{Name: OwnerTypeName, Value: "user"},
	})
	r.Contains(fields, routing.CustomField{Name: WatcherScenarioName, Value: watcherScenarioValue})
	r.Contains(fields, routing.CustomField{Name: RepositoryIDName, Value: "1"})
	r.Contains(fields, routing.CustomField{Name: OwnerTypeName, Value: "user"})
	r.Contains(fields, routing.CustomField{Name: OwnerIDName, Value: "123"})

	filters := builder.Filters()
	r.Equal([]routing.SettingFilter{
		{
			SubjectType: "any",
			Trigger:     "any",
			MatchRules:  []routing.SettingMatchRule{{Attribute: WatchActivityMatchRuleName, Value: WatchActivityMatchRuleValue, MatchRule: "eq"}},
		},
	}, filters)
}

func Test_IgnoreThredad(t *testing.T) {
	r := require.New(t)

	expectedChannel := map[string]*matchengine.Channel{
		"ALL": {Channel: "ALL", Enabled: false},
	}

	cases := []struct {
		name                 string
		ignoreBuilder        ignoreThreadBuilder
		expectedFilters      []routing.SettingFilter
		expectedCustomFields []routing.CustomField
	}{
		{
			name: "with issue thread",
			ignoreBuilder: ignoreThreadBuilder{
				title:        "Thread ignore setting",
				reason:       "test_reason",
				repositoryID: 1,
				threadType:   "issue",
				threadID:     "123",
				ownerID:      1,
				ownerType:    "user",
			},
			expectedFilters: []routing.SettingFilter{
				{
					Reason:      "author",
					SubjectType: "any",
					Trigger:     "any",
					MatchRules:  []routing.SettingMatchRule{},
				},
				{
					Reason:      "comment",
					SubjectType: "any",
					Trigger:     "any",
					MatchRules:  []routing.SettingMatchRule{},
				},
				{
					Reason:      "manual",
					SubjectType: "any",
					Trigger:     "any",
					MatchRules:  []routing.SettingMatchRule{},
				},
			},
			expectedCustomFields: []routing.CustomField{
				{Name: CategoryName, Value: CategoryThreadValue},
				{Name: ThreadIDName, Value: "123"},
				{Name: ThreadTypeName, Value: "issue"},
				{Name: OwnerIDName, Value: "1"},
				{Name: OwnerTypeName, Value: "user"},
				{Name: RepositoryIDName, Value: "1"},
			},
		},
		{
			name: "with empty repository id",
			ignoreBuilder: ignoreThreadBuilder{
				title:        "Thread ignore setting",
				reason:       "test_reason",
				repositoryID: 0,
				threadType:   "issue",
				threadID:     "123",
				ownerID:      1,
				ownerType:    "user",
			},
			expectedFilters: []routing.SettingFilter{
				{
					Reason:      "author",
					SubjectType: "any",
					Trigger:     "any",
					MatchRules:  []routing.SettingMatchRule{},
				},
				{
					Reason:      "comment",
					SubjectType: "any",
					Trigger:     "any",
					MatchRules:  []routing.SettingMatchRule{},
				},
				{
					Reason:      "manual",
					SubjectType: "any",
					Trigger:     "any",
					MatchRules:  []routing.SettingMatchRule{},
				},
			},
			expectedCustomFields: []routing.CustomField{
				{Name: CategoryName, Value: CategoryThreadValue},
				{Name: ThreadIDName, Value: "123"},
				{Name: ThreadTypeName, Value: "issue"},
				{Name: OwnerIDName, Value: "1"},
				{Name: OwnerTypeName, Value: "user"},
			},
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			builder := test.ignoreBuilder

			r.Equal("Thread ignore setting", builder.Title())
			r.Equal(CategoryThreadValue, builder.Category())

			// @dev-tim 2022-10-21 this is known hack around
			// ignoring logic for threads. We took shortcuts for Gists,
			// but we need to solve this problem ASAP as followup.
			r.Equal("", builder.Reason())
			cfFields := builder.CustomFields(nil)
			r.Equal(test.expectedCustomFields, cfFields)

			filters := builder.Filters()
			r.Equal(test.expectedFilters, filters)

			r.Equal(expectedChannel, builder.Channels())
		})
	}
}
