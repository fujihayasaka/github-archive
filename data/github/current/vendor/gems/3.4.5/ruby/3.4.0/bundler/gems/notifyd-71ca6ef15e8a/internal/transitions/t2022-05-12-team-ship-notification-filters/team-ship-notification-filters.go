package t2022_05_12_team_ship_notification_filters //nolint:revive,stylecheck // allow underscores

import (
	"context"
	"strconv"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"

	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/routing"
)

// TeamShippedNotificationFilters is a transition that adds some default notification filters
// for each member of the Notifications team, in order to test our new routing settings
type TeamShippedNotificationFilters struct {
	telem   *telemetry.Provider
	db      mysql.DB
	storage routing.Storage
}

// NewTeamShippedNotificationFilters creates a new instance of the transition.
func NewTeamShippedNotificationFilters(telem *telemetry.Provider, db mysql.DB, storage routing.Storage) *TeamShippedNotificationFilters {
	return &TeamShippedNotificationFilters{telem: telem, db: db, storage: storage}
}

// Run runs the transition.
func (t *TeamShippedNotificationFilters) Run(ctx context.Context, isDryRun bool) error {
	logger := t.telem.Logger.WithContext(ctx)

	if !isDryRun {
		_, err := t.db.Write.Exec(`
    DELETE FROM routing_setting_match_rules;
		DELETE FROM routing_settings;
		DELETE FROM meta_routing_settings;
   `)
		if err != nil {
			logger.Error("Unable to cleanup routing settings team data")
			return err
		}
	}

	logger.Info("Cleanup of routing settings data", kvp.Bool("dry_run", isDryRun))

	// run all the use cases for this transition
	logger.Info("Going to create a couple of use cases", kvp.Int("count", len(usecases)))
	for _, uc := range usecases {
		t.execute(ctx, uc, isDryRun)
	}

	return nil
}

func (t *TeamShippedNotificationFilters) execute(ctx context.Context, mrs *routing.MetaSetting, isDryRun bool) {
	t.telem.Logger.WithContext(ctx).Info("Creating routing setting", kvp.Any("mrs", mrs))
	if isDryRun {
		return
	}

	_, err := t.storage.Create(ctx, mrs)
	if err != nil {
		t.telem.Logger.WithContext(ctx).WithError(err).Error("failed to create meta routing setting", kvp.Any("mrs", mrs))
	}
}

func mrsSuccessOnlyCIActivity(user string, repositories, reasons []string, channels dto.ChannelsMap) *routing.MetaSetting {
	return mrsCIActivityWithFailedStatus(user, repositories, reasons, channels, false)
}

func mrsFailedCIActivity(user string, repositories, reasons []string, channels dto.ChannelsMap) *routing.MetaSetting {
	return mrsCIActivityWithFailedStatus(user, repositories, reasons, channels, true)
}

func mrsCIActivityWithFailedStatus(user string, repositories, reasons []string, channels dto.ChannelsMap, isFailedAttr bool) *routing.MetaSetting {
	topics := buildTopics(repositories)

	var filters []routing.SettingFilter
	for _, reason := range reasons {
		filters = append(filters, routing.SettingFilter{
			Reason: reason,
			MatchRules: []routing.SettingMatchRule{
				{Attribute: "failed", Value: strconv.FormatBool(isFailedAttr), MatchRule: "eq"},
			},
		})
	}

	return &routing.MetaSetting{
		UserID: team[user],
		Name:   "Failed CI filter for " + user,
		Details: routing.SettingDetails{
			Channels: channels,
			Topics:   topics,
			Filters:  filters,
		},
	}
}

func mrsCIActivity(user string, repository, reasons []string, channels dto.ChannelsMap) *routing.MetaSetting {
	topics := buildTopics(repository)

	var reasonFilters []routing.SettingFilter
	for _, reason := range reasons {
		reasonFilters = append(reasonFilters, routing.SettingFilter{
			Reason: reason,
		})
	}

	return &routing.MetaSetting{
		UserID: team[user],
		Name:   "Any CI filter for " + user,
		Details: routing.SettingDetails{
			Channels: channels,
			Topics:   topics,
			Filters:  reasonFilters,
		},
	}
}

func buildTopics(repository []string) []routing.Topic {
	var topics []routing.Topic

	if len(repository) == 0 {
		topics = append(topics, routing.Topic{Type: "any", Value: "any"})
	} else {
		for _, tr := range repository {
			topics = append(topics, routing.Topic{Type: "repository", Value: strconv.Itoa(repos[tr])})
		}
	}
	return topics
}
