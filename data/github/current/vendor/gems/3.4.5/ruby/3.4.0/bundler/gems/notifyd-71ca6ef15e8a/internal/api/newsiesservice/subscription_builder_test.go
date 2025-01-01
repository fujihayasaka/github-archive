package newsiesservice

import (
	"testing"

	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/subscriptions"
)

func Test_listBuilder(t *testing.T) {
	r := require.New(t)
	builder := listBuilder{
		refType: "repository",
		refID:   1,
	}

	r.Equal("List subscription", builder.Title())
	r.Equal("all", builder.Category())
	r.Equal(ListReason, builder.Reason())

	cfFields, err := builder.CustomFields([]subscriptions.CustomField{
		{Name: OwnerIDName, Value: "123"},
		{Name: OwnerTypeName, Value: "user"},
	})
	r.NoError(err)
	r.Contains(cfFields, subscriptions.CustomField{Name: WatcherScenarioName, Value: watcherScenarioValue})
	r.Contains(cfFields, subscriptions.CustomField{Name: RepositoryIDName, Value: "1"})
	r.Contains(cfFields, subscriptions.CustomField{Name: OwnerTypeName, Value: "user"})
	r.Contains(cfFields, subscriptions.CustomField{Name: OwnerIDName, Value: "123"})

	filters, err := builder.Filters()
	r.NoError(err)
	r.Equal([]subscriptions.Filter{
		{
			SubjectType: "any",
			Trigger:     "any",
			MatchRules:  []subscriptions.MatchRule{{Attribute: WatchActivityMatchRuleName, Value: WatchActivityMatchRuleValue, MatchRule: "eq"}},
		},
	}, filters)
}

func Test_threadTypeBuilder(t *testing.T) {
	r := require.New(t)

	cases := []struct {
		name                            string
		threadTypes                     []ThreadType
		expected                        []subscriptions.Filter
		expectedCustomFieldsThreadTypes []string
	}{
		{
			name:        "with Issue type",
			threadTypes: []ThreadType{Issue},
			expected: []subscriptions.Filter{
				{
					SubjectType: "any",
					Trigger:     "any",
					MatchRules: []subscriptions.MatchRule{
						subscriptions.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue),
						subscriptions.RuleEQ(ThreadTypeMatchRuleName, "issue"),
					},
				},
			},
			expectedCustomFieldsThreadTypes: []string{"issue"},
		},
		{
			name:        "with Pull Request type",
			threadTypes: []ThreadType{PullRequest},
			expected: []subscriptions.Filter{
				{
					SubjectType: "any",
					Trigger:     "any",
					MatchRules: []subscriptions.MatchRule{
						subscriptions.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue),
						subscriptions.RuleEQ(ThreadTypeMatchRuleName, "pull_request"),
					},
				},
			},
			expectedCustomFieldsThreadTypes: []string{"pull_request"},
		},
		{
			name:        "with Discussions type",
			threadTypes: []ThreadType{Discussion},
			expected: []subscriptions.Filter{
				{
					SubjectType: "any",
					Trigger:     "any",
					MatchRules: []subscriptions.MatchRule{
						subscriptions.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue),
						subscriptions.RuleEQ(ThreadTypeMatchRuleName, "discussion"),
					},
				},
			},
			expectedCustomFieldsThreadTypes: []string{"discussion"},
		},
		{
			name:        "with Release type",
			threadTypes: []ThreadType{Release},
			expected: []subscriptions.Filter{
				{
					SubjectType: "any",
					Trigger:     "any",
					MatchRules: []subscriptions.MatchRule{
						subscriptions.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue),
						subscriptions.RuleEQ(ThreadTypeMatchRuleName, "release"),
					},
				},
			},
			expectedCustomFieldsThreadTypes: []string{"release"},
		},
		{
			name:        "with SecurityAlert type",
			threadTypes: []ThreadType{SecurityAlert},
			expected: []subscriptions.Filter{
				{
					SubjectType: "any",
					Trigger:     "any",
					MatchRules: []subscriptions.MatchRule{
						subscriptions.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue),
						subscriptions.RuleEQ(ThreadTypeMatchRuleName, "security_alert"),
					},
				},
			},
			expectedCustomFieldsThreadTypes: []string{"security_alert"},
		},
		{
			name:        "with several thread types",
			threadTypes: []ThreadType{Issue, SecurityAlert},
			expected: []subscriptions.Filter{
				{
					SubjectType: "any",
					Trigger:     "any",
					MatchRules: []subscriptions.MatchRule{
						subscriptions.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue),
						subscriptions.RuleEQ(ThreadTypeMatchRuleName, "issue"),
					},
				},
				{
					SubjectType: "any",
					Trigger:     "any",
					MatchRules: []subscriptions.MatchRule{
						subscriptions.RuleEQ(WatchActivityMatchRuleName, WatchActivityMatchRuleValue),
						subscriptions.RuleEQ(ThreadTypeMatchRuleName, "security_alert"),
					},
				},
			},
			expectedCustomFieldsThreadTypes: []string{"issue", "security_alert"},
		},
	}

	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			builder := ThreadTypeBuilder{
				refID:   1,
				refType: "repository",
				types:   test.threadTypes,
			}

			r.Equal("Thread Type subscription", builder.Title())
			r.Equal(CategoryThreadTypeValue, builder.Category())
			r.Equal(ThreadTypeReason, builder.Reason())

			cfFields, err := builder.CustomFields([]subscriptions.CustomField{
				{Name: OwnerIDName, Value: "123"},
				{Name: OwnerTypeName, Value: "user"},
			})
			r.NoError(err)
			r.Contains(cfFields, subscriptions.CustomField{Name: WatcherScenarioName, Value: watcherScenarioValue})
			r.Contains(cfFields, subscriptions.CustomField{Name: RepositoryIDName, Value: "1"})
			r.Contains(cfFields, subscriptions.CustomField{Name: OwnerTypeName, Value: "user"})
			r.Contains(cfFields, subscriptions.CustomField{Name: OwnerIDName, Value: "123"})
			for _, expectedThreadType := range test.expectedCustomFieldsThreadTypes {
				r.Contains(cfFields, subscriptions.CustomField{Name: ThreadTypeName, Value: expectedThreadType})
			}

			filters, err := builder.Filters()
			r.NoError(err)
			r.Equal(test.expected, filters)
		})
	}

	t.Run("for unknown threadTypes", func(t *testing.T) {
		builder := ThreadTypeBuilder{types: []ThreadType{ThreadType(-1)}}

		_, err := builder.Filters()
		r.ErrorIs(err, errUnknownType)
	})
}

func Test_threadBuilder(t *testing.T) {
	r := require.New(t)

	cases := []struct {
		name                 string
		threadBuilder        ThreadBuilder
		expectedFilters      []subscriptions.Filter
		expectedCustomFields []subscriptions.CustomField
	}{
		{
			name: "with issue thread",
			threadBuilder: ThreadBuilder{
				title:        "Thread subscription",
				reason:       "test_reason",
				repositoryID: 1,
				threadType:   "issue",
				threadID:     "123",
				ownerID:      1,
				ownerType:    "user",
			},
			expectedFilters: []subscriptions.Filter{
				{
					SubjectType: "any",
					Trigger:     "any",
					MatchRules: []subscriptions.MatchRule{
						subscriptions.RuleEQ(ThreadParticipantActivityName, "true"),
					},
				},
			},
			expectedCustomFields: []subscriptions.CustomField{
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
			threadBuilder: ThreadBuilder{
				title:        "Thread subscription",
				reason:       "test_reason",
				repositoryID: 0,
				threadType:   "issue",
				threadID:     "123",
				ownerID:      1,
				ownerType:    "user",
			},
			expectedFilters: []subscriptions.Filter{
				{
					SubjectType: "any",
					Trigger:     "any",
					MatchRules: []subscriptions.MatchRule{
						subscriptions.RuleEQ(ThreadParticipantActivityName, "true"),
					},
				},
			},
			expectedCustomFields: []subscriptions.CustomField{
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
			builder := test.threadBuilder

			r.Equal("Thread subscription", builder.Title())
			r.Equal(CategoryThreadValue, builder.Category())
			r.Equal("test_reason", builder.Reason())
			cfFields, err := builder.CustomFields(nil)
			r.NoError(err)
			r.Equal(test.expectedCustomFields, cfFields)

			filters, err := builder.Filters()
			r.NoError(err)
			r.Equal(test.expectedFilters, filters)
		})
	}
}
