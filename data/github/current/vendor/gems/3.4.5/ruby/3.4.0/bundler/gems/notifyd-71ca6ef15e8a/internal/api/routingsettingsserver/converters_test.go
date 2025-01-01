package routingsettingsserver

import (
	"sort"
	"testing"

	"github.com/benbjohnson/clock"

	"github.com/github/notifyd/internal/pkg/mysql"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/routing"

	testsuite "github.com/stretchr/testify/suite"

	api_pb "github.com/github/notifyd/proto/services/routingsettings"
)

type ConvertersTestSuite struct {
	testsuite.Suite
}

func (suite *ConvertersTestSuite) TestPbToReplaceByCustomFields() {
	testCase := []struct {
		name     string
		input    []*api_pb.CustomField
		expected []routing.CustomField
	}{
		{
			name:     "no data",
			input:    []*api_pb.CustomField{},
			expected: []routing.CustomField{},
		},
		{
			name: "both name and value present",
			input: []*api_pb.CustomField{
				{Name: "1", Value: "1"},
				{Name: "2", Value: "2"},
			},
			expected: []routing.CustomField{
				{Name: "1", Value: "1"},
				{Name: "2", Value: "2"},
			},
		},
		{
			name: "repeating values are present",
			input: []*api_pb.CustomField{
				{Name: "1", Value: "1"},
				{Name: "1", Value: "3"},
				{Name: "2", Value: "2"},
			},
			expected: []routing.CustomField{
				{Name: "1", Value: "1"},
				{Name: "1", Value: "3"},
				{Name: "2", Value: "2"},
			},
		},
	}

	for _, test := range testCase {
		suite.Run(test.name, func() {
			actual := pbToCustomFields(test.input)
			suite.Require().Len(actual, len(test.expected))

			for idx, field := range test.expected {
				suite.Require().Equal(field.Name, actual[idx].Name)
				suite.Require().Equal(field.Value, actual[idx].Value)
			}
		})
	}
}

func (suite *ConvertersTestSuite) TestPbToMetaSubscriptions() {
	testCase := []struct {
		name     string
		input    []*api_pb.CreateRequest
		expected []*routing.MetaSetting
	}{
		{
			name:     "no data",
			input:    []*api_pb.CreateRequest{},
			expected: []*routing.MetaSetting{},
		},
		{
			name: "all fields filled in",
			input: []*api_pb.CreateRequest{
				{
					UserId: 1,
					Topics: []*api_pb.Topic{
						{Type: "repository", Value: "123"},
						{Type: "repository", Value: "456"},
					},
					Filters: []*api_pb.Filter{
						{
							SubjectType: "issue",
							Trigger:     "created",
							MatchRules: []*api_pb.MatchRule{
								{Attribute: "has_label", Value: "1", MatchRule: "list"},
								{Attribute: "title", Value: "sub", MatchRule: "contains"},
							},
						},
						{
							SubjectType: "pull_request",
							Trigger:     "created",
							MatchRules: []*api_pb.MatchRule{
								{Attribute: "has_label", Value: "1", MatchRule: "list"},
								{Attribute: "title", Value: "sub", MatchRule: "contains"},
							},
						},
					},
					Channels: []*api_pb.Channel{
						{Name: "EMAIL", Enabled: false},
						{Name: "PUSH", Enabled: true},
					},
					CustomFields: []*api_pb.CustomField{
						{Name: "repository_id", Value: "123"},
						{Name: "label_id", Value: "1"},
					},
				},
			},
			expected: []*routing.MetaSetting{
				{
					UserID: 1,
					Details: routing.SettingDetails{
						Topics: []routing.Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						CustomFields: []routing.CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "label_id", Value: "1"},
						},
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: false},
							"PUSH":  {Channel: "PUSH", Enabled: true},
						},
						Filters: []routing.SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []routing.SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []routing.SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
					},
				},
			},
		},
	}

	for _, test := range testCase {
		suite.Run(test.name, func() {
			actual := pbToMetaSettings(test.input)
			suite.Require().Len(actual, len(test.expected))

			for idx, expectedSetting := range test.expected {
				routing.AssertMetaSettingIsSaved(suite.Require(), expectedSetting, actual[idx])
			}
		})
	}
}

func (suite *ConvertersTestSuite) TestPbNewSettingsToMetaSubscriptions() {
	testCase := []struct {
		name     string
		input    []*api_pb.Setting
		expected []*routing.MetaSetting
	}{
		{
			name:     "no data",
			input:    []*api_pb.Setting{},
			expected: []*routing.MetaSetting{},
		},
		{
			name: "all fields filled in",
			input: []*api_pb.Setting{
				{
					Topics: []*api_pb.Topic{
						{Type: "repository", Value: "123"},
						{Type: "repository", Value: "456"},
					},
					Filters: []*api_pb.Filter{
						{
							SubjectType: "issue",
							Trigger:     "created",
							MatchRules: []*api_pb.MatchRule{
								{Attribute: "has_label", Value: "1", MatchRule: "list"},
								{Attribute: "title", Value: "sub", MatchRule: "contains"},
							},
						},
						{
							SubjectType: "pull_request",
							Trigger:     "created",
							MatchRules: []*api_pb.MatchRule{
								{Attribute: "has_label", Value: "1", MatchRule: "list"},
								{Attribute: "title", Value: "sub", MatchRule: "contains"},
							},
						},
					},
					Channels: []*api_pb.Channel{
						{Name: "EMAIL", Enabled: false},
						{Name: "PUSH", Enabled: true},
					},
					CustomFields: []*api_pb.CustomField{
						{Name: "repository_id", Value: "123"},
						{Name: "label_id", Value: "1"},
					},
				},
			},
			expected: []*routing.MetaSetting{
				{
					UserID: 1,
					Details: routing.SettingDetails{
						Topics: []routing.Topic{
							{Type: "repository", Value: "123"},
							{Type: "repository", Value: "456"},
						},
						CustomFields: []routing.CustomField{
							{Name: "repository_id", Value: "123"},
							{Name: "label_id", Value: "1"},
						},
						Channels: map[string]*matchengine_dto.Channel{
							"EMAIL": {Channel: "EMAIL", Enabled: false},
							"PUSH":  {Channel: "PUSH", Enabled: true},
						},
						Filters: []routing.SettingFilter{
							{
								SubjectType: "issue",
								Trigger:     "created",
								MatchRules: []routing.SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
							{
								SubjectType: "pull_request",
								Trigger:     "created",
								MatchRules: []routing.SettingMatchRule{
									{Attribute: "has_label", Value: "1", MatchRule: "list"},
									{Attribute: "title", Value: "sub", MatchRule: "contains"},
								},
							},
						},
					},
				},
			},
		},
	}
	var userID int64 = 1

	for _, test := range testCase {
		suite.Run(test.name, func() {
			actual := pbNewRoutingSettingToMetaSettings(userID, test.input)
			suite.Require().Len(actual, len(test.expected))
			for idx, expectedSetting := range test.expected {
				routing.AssertMetaSettingIsSaved(suite.Require(), expectedSetting, actual[idx])
			}
		})
	}
}

func (suite *ConvertersTestSuite) TestRoutingSettingToPB() {
	cl := clock.New()
	tests := map[string]struct {
		Setting *routing.MetaSetting
		PB      *api_pb.RoutingSetting
	}{
		"simple routing setting": {
			Setting: &routing.MetaSetting{
				Name:   "cool-name",
				ID:     1,
				UserID: 2,
				Details: routing.SettingDetails{
					Channels: map[string]*matchengine_dto.Channel{
						"email": {Enabled: true},
					},
					Topics: []routing.Topic{
						{Type: "", Value: ""},
					},
					Filters: []routing.SettingFilter{
						{SubjectType: "SubjectType", Trigger: "Trigger", Reason: "Reason",
							MatchRules: []routing.SettingMatchRule{
								{
									Attribute: "Attribute", Value: "Value", MatchRule: "MatchRule",
								},
							},
						},
					},
				},
				Timestamps: mysql.Timestamps{CreatedAt: cl.Now(), UpdatedAt: cl.Now()},
			},
			PB: &api_pb.RoutingSetting{
				Name:     "cool-name",
				Id:       1,
				UserId:   2,
				Channels: []*api_pb.Channel{{Name: "email", Enabled: true}},
				Topics:   []*api_pb.Topic{{Type: "", Value: ""}},
				Filters: []*api_pb.Filter{
					{
						SubjectType: "SubjectType",
						Trigger:     "Trigger",
						Reason:      "Reason",

						MatchRules: []*api_pb.MatchRule{
							{
								Attribute: "Attribute",
								Value:     "Value",
								MatchRule: "MatchRule",
							},
						},
					},
				},
				CreatedAt: cl.Now().Unix(),
			},
		},
		"routing settings with custom fields": {
			Setting: &routing.MetaSetting{
				Name:   "cool-name",
				ID:     1,
				UserID: 2,
				Details: routing.SettingDetails{
					CustomFields: []routing.CustomField{
						{Name: "repository", Value: "123"},
					},
				},
				Timestamps: mysql.Timestamps{CreatedAt: cl.Now(), UpdatedAt: cl.Now()},
			},
			PB: &api_pb.RoutingSetting{
				Name:   "cool-name",
				Id:     1,
				UserId: 2,
				CustomFields: []*api_pb.CustomField{
					{Name: "repository", Value: "123"},
				},
				CreatedAt: cl.Now().Unix(),
			},
		},
	}

	for name, tc := range tests {
		suite.Run(name, func() {
			res := routingSettingToPB(tc.Setting)
			suite.Require().Equal(tc.PB.Id, res.Id, "ID is not equal")
			suite.Require().Equal(tc.PB.Name, res.Name, "Name is not equal")
			suite.Require().Equal(tc.PB.UserId, res.UserId, "UserID is not equal")
			suite.Require().Equal(len(tc.PB.Channels), len(res.Channels), "not the same number of channels")
			suite.Require().Equal(len(tc.PB.Topics), len(res.Topics), "not the same number of topics")
			suite.Require().Equal(len(tc.PB.Filters), len(res.Filters), "not the same number of filters")

			sort.Slice(tc.PB.Filters, func(i, j int) bool { return tc.PB.Filters[i].Trigger < tc.PB.Filters[j].Trigger })
			sort.Slice(res.Filters, func(i, j int) bool { return res.Filters[i].Trigger < res.Filters[j].Trigger })

			for idx := range tc.PB.Filters {
				suite.Require().Equal(tc.PB.Filters[idx].Trigger, res.Filters[idx].Trigger, "filter triggers are not equal")
				suite.Require().Equal(tc.PB.Filters[idx].SubjectType, res.Filters[idx].SubjectType, "filter subject types are not equal")
				suite.Require().Equal(tc.PB.Filters[idx].Reason, res.Filters[idx].Reason, "filter reasons are not equal")

				suite.Require().Equal(len(tc.PB.Filters[idx].MatchRules), len(res.Filters[idx].MatchRules), "not the same number of match rules")

				sort.Slice(tc.PB.Filters[idx].MatchRules, func(i, j int) bool {
					return tc.PB.Filters[idx].MatchRules[i].Attribute < tc.PB.Filters[idx].MatchRules[j].Attribute
				})
				sort.Slice(res.Filters[idx].MatchRules, func(i, j int) bool {
					return res.Filters[idx].MatchRules[i].Attribute < res.Filters[idx].MatchRules[j].Attribute
				})

				for jdx := range tc.PB.Filters {
					suite.Require().Equal(tc.PB.Filters[jdx].MatchRules[jdx].Attribute, res.Filters[idx].MatchRules[jdx].Attribute, "match rule attributes are not equal")
					suite.Require().Equal(tc.PB.Filters[jdx].MatchRules[jdx].MatchRule, res.Filters[idx].MatchRules[jdx].MatchRule, "match rules are not equal")
					suite.Require().Equal(tc.PB.Filters[jdx].MatchRules[jdx].Value, res.Filters[idx].MatchRules[jdx].Value, "match rule values are not equal")
				}
			}

			suite.Require().Equal(len(tc.PB.Filters), len(res.Filters), "not the same number of filters")

			suite.Require().Equal(len(tc.PB.CustomFields), len(res.CustomFields), "not the same number of custom fields")
			suite.Require().Equal(tc.PB.CreatedAt, res.CreatedAt, "CreatedAt is not equal")
		})
	}
}

func TestConvertersTestSuite(t *testing.T) {
	testsuite.Run(t, new(ConvertersTestSuite))
}
