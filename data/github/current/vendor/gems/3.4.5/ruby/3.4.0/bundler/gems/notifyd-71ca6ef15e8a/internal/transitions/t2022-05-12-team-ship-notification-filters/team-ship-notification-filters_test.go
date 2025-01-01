package t2022_05_12_team_ship_notification_filters //nolint:revive,stylecheck // allow underscores

import (
	"context"
	"sort"
	"strconv"
	"testing"

	"github.com/benbjohnson/clock"
	"github.com/jmoiron/sqlx"
	"github.com/stretchr/testify/require"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/mysql/testhelper"
	"github.com/github/notifyd/internal/pkg/o11y/logs"
	"github.com/github/notifyd/internal/pkg/routing"
)

func TestRun(t *testing.T) {
	r := require.New(t)
	ctx := context.Background()

	db, dbCleanup := testhelper.PrepareTestDB(ctx)
	defer dbCleanup()
	storage := routing.NewStorage(clock.NewMock(), logs.NullTelem, db)
	transition := NewTeamShippedNotificationFilters(logs.NullTelem, db, storage)

	var testCases = []struct {
		// input parameters
		name         string
		userID       int64
		repositoryID []string
		mrs          *routing.MetaSetting

		// validation parameters
		settingLength    int // how many settings do we expect
		matchRulesLength int // how many match rules do we expect
	}{
		{
			name:             "create any CI activity notification for gerbenjacobs on github/notifyd",
			userID:           team["gerbenjacobs"],
			repositoryID:     []string{strconv.Itoa(repos["github/notifyd"])},
			mrs:              mrsCIActivity("gerbenjacobs", []string{"github/notifyd"}, []string{"ci_activity"}, channelEmail(true)),
			settingLength:    1,
			matchRulesLength: 0,
		},
		{
			name:             "create failed CI activity notification for gerbenjacobs on github/notifyd",
			userID:           team["franciscoj"],
			repositoryID:     []string{strconv.Itoa(repos["github/notifyd"])},
			mrs:              mrsFailedCIActivity("franciscoj", []string{"github/notifyd"}, []string{"ci_activity"}, channelEmail(true)),
			settingLength:    1,
			matchRulesLength: 1,
		},
		{
			name:             "disable CI activity notification for dev-tim on github/notifyd and team-discussions/a-repo",
			userID:           team["dev-tim"],
			repositoryID:     []string{strconv.Itoa(repos["github/notifyd"]), strconv.Itoa(repos["team-discussions/a-repo"])},
			mrs:              mrsCIActivity("dev-tim", []string{"github/notifyd", "team-discussions/a-repo"}, []string{"ci_activity"}, channelEmail(false)),
			settingLength:    2,
			matchRulesLength: 0,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			if err := testhelper.TruncateAllTables(ctx, db); err != nil {
				r.NoError(err, "truncate test db: %s", err)
			}
			err := transition.Run(ctx, true)
			r.NoError(err)

			// execute this MetaSetting
			transition.execute(ctx, tc.mrs, false)

			// retrieve settings
			settings, err := getRoutingSettings(ctx, db, tc.userID)
			r.NoError(err)

			// validate results
			r.Len(settings, tc.settingLength)
			r.Equal(tc.userID, settings[0].UserID)
			r.Equal("repository", settings[0].TopicType)
			r.Equal(tc.repositoryID, topicValues(settings))
			r.Len(settings[0].MatchRules, tc.matchRulesLength)
		})
	}
}

// topicValues is a helper function that returns a sorted list of topic values
func topicValues(settings []*routing.Setting) (values []string) {
	for _, s := range settings {
		values = append(values, s.TopicValue)
	}
	sort.Strings(values)
	return //nolint:revive // It is OK, it is small enough
}

// getRoutingSettings gets all the routing settings for a user ID
// copied from /internal/pkg/routing/service.go
func getRoutingSettings(ctx context.Context, db mysql.DB, userID int64) ([]*routing.Setting, error) {
	var routingSettings []*routing.Setting
	err := db.Write.SelectContext(ctx, &routingSettings, "SELECT * FROM routing_settings WHERE user_id = ?", userID)
	if err != nil {
		return []*routing.Setting{}, errors.Wrap(err, "Unable to fetch routing settings")
	}

	if len(routingSettings) == 0 {
		return routingSettings, nil
	}

	routingSettingsToIDsMap := map[int64]*routing.Setting{}
	var id []int64
	for _, item := range routingSettings {
		id = append(id, item.ID)
		routingSettingsToIDsMap[item.ID] = item
	}

	selectMatchRulesQuery := "SELECT * FROM routing_setting_match_rules WHERE routing_setting_id IN (?)"

	query, args, err := sqlx.In(selectMatchRulesQuery, id)
	if err != nil {
		return nil, errors.Wrapf(err, "error bulding select match rules query")
	}

	var matchRules []routing.SettingMatchRule
	query = db.Write.Rebind(query)
	err = db.Write.SelectContext(ctx, &matchRules, query, args...)
	if err != nil {
		return nil, errors.Wrapf(err, "error executing select match rules query")
	}

	for _, matchRule := range matchRules {
		routingSettingsToIDsMap[matchRule.RoutingSettingID].MatchRules = append(routingSettingsToIDsMap[matchRule.RoutingSettingID].MatchRules, matchRule)
	}

	var routingSettingWithMatchRules []*routing.Setting
	for _, subscription := range routingSettingsToIDsMap {
		routingSettingWithMatchRules = append(routingSettingWithMatchRules, subscription)
	}

	sort.Slice(routingSettingWithMatchRules, func(i, j int) bool {
		return routingSettingWithMatchRules[i].ID < routingSettingWithMatchRules[j].ID
	})

	return routingSettingWithMatchRules, nil
}
