package routing

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/Masterminds/squirrel"
	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/jmoiron/sqlx"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/mysql"
	mysqlquery "github.com/github/notifyd/internal/pkg/mysql/query"
	"github.com/github/notifyd/internal/pkg/mysql/transaction"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/notify/matchengine"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/pagination"
)

const paginationID = "rs.id"

// Storage represents a routing settings storage.
type Storage interface {
	GetSettings(ctx context.Context, fields []CustomField, page pagination.Page) ([]*MetaSetting, pagination.Pages, error)
	GetSettingsForUsers(ctx context.Context, userIDs []int64, fields []CustomField, page pagination.Page) ([]*MetaSetting, pagination.Pages, error)
	Create(ctx context.Context, metaRotingSetting *MetaSetting) (*MetaSetting, error)
	BatchCreateAndDelete(ctx context.Context, toCreate []*MetaSetting, toDelete []int64) ([]*MetaSetting, error)
	BatchReplace(ctx context.Context, userID int64, settingsToCreate []*MetaSetting, fields []CustomField) ([]int64, error)
	Delete(ctx context.Context, userID int64, fields []CustomField) error

	GetMatchingEntries(ctx context.Context, potentialRecipients []int64, reasons []string, msgMatchFields notify.MessageMatchFields) ([]*matchengine.MatchedEntry, error)
	GetChannels(ctx context.Context, routingSettingIDs []int64) (map[int64][]matchengine_dto.Channel, error)
}

type storage struct {
	clock   clockpkg.Clock
	telem   *telemetry.Provider
	dbWrite *sqlx.DB
	dbRead  *sqlx.DB
}

// NewStorage creates a new routing settings storage.
func NewStorage(clock clockpkg.Clock, telem *telemetry.Provider, db mysql.DB) Storage {
	return &storage{
		clock:   clock,
		telem:   telem,
		dbWrite: db.Write,
		dbRead:  db.Read,
	}
}

func (s *storage) BatchCreateAndDelete(ctx context.Context, toCreate []*MetaSetting, toDelete []int64) ([]*MetaSetting, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	return mysql.WithRetries(ctx, s.clock, s.telem, func(c context.Context) ([]*MetaSetting, error) {
		var settings []*MetaSetting
		tx := transaction.New()

		err := tx.Run(ctx, s.dbWrite, func(txx *sqlx.Tx) error {
			savedSettings, err := s.batchCreateAndDeleteInTx(ctx, txx, toCreate, toDelete)
			if err != nil {
				return errors.Wrap(err, "batch create and delete routing settings failed")
			}

			settings = append(settings, savedSettings...)

			return nil
		})

		return settings, err
	})
}

func (s *storage) BatchReplace(ctx context.Context, userID int64, toCreate []*MetaSetting, fields []CustomField) ([]int64, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	return mysql.WithRetries(ctx, s.clock, s.telem, func(c context.Context) ([]int64, error) {
		var metaSettings []*MetaSetting
		tx := transaction.New()

		err := tx.Run(ctx, s.dbWrite, func(txx *sqlx.Tx) error {
			err := s.deleteByCustomFieldsInTx(ctx, txx, userID, fields)
			if err != nil {
				return errors.Wrap(err, "delete by custom fields failed")
			}

			for _, setting := range toCreate {
				created, err := s.createInTx(ctx, txx, setting)
				if err != nil {
					return errors.Wrap(err, "create routing settings failed")
				}

				metaSettings = append(metaSettings, created)
			}

			return nil
		})

		if err != nil {
			return []int64{}, err
		}

		metaSettingIDs := make([]int64, len(metaSettings))
		for idx, metaSettingID := range metaSettings {
			metaSettingIDs[idx] = metaSettingID.ID
		}

		return metaSettingIDs, nil
	})
}

func (s *storage) batchCreateAndDeleteInTx(ctx context.Context, txx *sqlx.Tx, toCreate []*MetaSetting, toDelete []int64) ([]*MetaSetting, error) {
	err := s.deleteInTx(ctx, txx, toDelete)
	if err != nil {
		return []*MetaSetting{}, errors.Wrap(err, "delete routing settings failed")
	}

	var savedMetaRoutingSettings []*MetaSetting
	for _, metaRoutingSetting := range toCreate {
		savedMetaRoutingSetting, err := s.createInTx(ctx, txx, metaRoutingSetting)

		if err != nil {
			return []*MetaSetting{}, errors.Wrap(err, "create routing settings failed")
		}

		savedMetaRoutingSettings = append(savedMetaRoutingSettings, savedMetaRoutingSetting)
	}

	return savedMetaRoutingSettings, nil
}

func (s *storage) createInTx(ctx context.Context, txx *sqlx.Tx, metaSetting *MetaSetting) (*MetaSetting, error) {
	logger := s.telem.Logger.WithContext(ctx)

	savedMetaRoutingSetting, err := createMetaRoutingSettingInTx(ctx, s.clock, txx, metaSetting)
	if err != nil {
		return nil, errors.Wrap(err, "creating metaRouting setting")
	}
	logger.WithFields(kvp.Int64("gh.notifyd.meta_routing_setting.id", savedMetaRoutingSetting.ID)).
		Debug("Routing setting DB client - Create: saved meta routing settings")

	// we can see if meta routing settings can be converted even before starting Tx
	convertedRoutingSettings, err := metaSetting.Settings(s.clock)
	if err != nil {
		return nil, errors.Wrap(err, "failed to convert routing settings")
	}

	logger.Debug("Routing setting DB client - Create: converted meta routing settings to routing settings records")

	savedRoutingSettings, err := createRoutingSettingsInTx(ctx, txx, s.clock, convertedRoutingSettings)
	if err != nil {
		return nil, errors.Wrap(err, "create routing settings failed")
	}
	logger.WithFields(kvp.Int("gh.notifyd.meta_routing_setting.count", len(savedRoutingSettings))).
		Debug("Routing setting DB client - Create: saved routing settings")

	return savedMetaRoutingSetting, nil
}

func (s *storage) Create(ctx context.Context, metaRoutingSetting *MetaSetting) (*MetaSetting, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	return mysql.WithRetries(ctx, s.clock, s.telem, func(c context.Context) (*MetaSetting, error) {
		var newRoutingSetting *MetaSetting
		tx := transaction.New()

		err := tx.Run(ctx, s.dbWrite, func(txx *sqlx.Tx) error {
			var err error
			newRoutingSetting, err = s.createInTx(ctx, txx, metaRoutingSetting)

			return err
		})

		if err != nil {
			return nil, err
		}

		return newRoutingSetting, nil
	})
}

func saveChannelsInTx(ctx context.Context, txx *sqlx.Tx, clock clockpkg.Clock, routingSetting *Setting) error {
	for _, channel := range routingSetting.Channels {
		channel.RoutingSettingID = routingSetting.ID
		channel.UpdateTimestamps(clock)

		sql, args, err := squirrel.Insert("routing_setting_channels").
			Columns("routing_setting_id", "channel", "enabled", "created_at", "updated_at").
			Values(
				channel.RoutingSettingID,
				channel.Channel,
				channel.Enabled,
				channel.CreatedAt,
				channel.UpdatedAt,
			).
			ToSql()

		if err != nil {
			return errors.Wrap(err, "create routing setting channels SQL query failed")
		}

		sqlResult, err := txx.ExecContext(ctx, sql, args...)

		if err != nil {
			return errors.Wrap(err, "create routing setting channels failed")
		}

		id, err := sqlResult.LastInsertId()
		if err != nil {
			return errors.Wrap(err, "create routing setting channels - could not get last id")
		}

		channel.ID = id
	}
	return nil
}

// Delete the settings by custom fields.
//
// Deletion is optimized to a single multi-table delete query to avoid the current multiple query transaction.
// NOTE(abeaumont): This is experimental for now, please don't use.
//
//nolint:revive // ignore unhandled error for experimental code
func (s *storage) Delete(ctx context.Context, userID int64, fields []CustomField) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	_, err := mysql.WithRetries(ctx, s.clock, s.telem, mysql.ToCallback(func(c context.Context) error {
		if len(fields) == 0 {
			return nil
		}
		// Unfortunately squirrel doesn't have support for multi-table deletions,
		// see https://github.com/Masterminds/squirrel/pull/295.
		var query strings.Builder
		var args []any
		query.WriteString("DELETE mrs, rs, mr, c, cf ")
		query.WriteString("FROM meta_routing_settings AS mrs ")
		query.WriteString("JOIN routing_settings AS rs ")
		query.WriteString("JOIN routing_setting_match_rules AS mr ")
		query.WriteString("JOIN routing_setting_channels AS c ")
		query.WriteString("JOIN routing_setting_custom_fields AS cf ")
		for i := range fields {
			query.WriteString(fmt.Sprintf("JOIN routing_setting_custom_fields AS cf%d ", i))
		}
		query.WriteString("WHERE mrs.user_id = ? ")
		args = append(args, userID)
		query.WriteString("AND mrs.id = `rs`.meta_id AND mrs.user_id = `rs`.user_id ")
		query.WriteString("AND rs.id = `mr`.routing_setting_id ")
		query.WriteString("AND rs.id = `c`.routing_setting_id ")
		query.WriteString("AND mrs.id = `cf`.meta_id AND mrs.user_id = `cf`.user_id ")
		for i, field := range fields {
			query.WriteString(fmt.Sprintf("AND mrs.id = `cf%d`.meta_id AND mrs.user_id = `cf%d`.user_id ", i, i))
			query.WriteString(fmt.Sprintf("AND cf%d.name = ? ", i))
			args = append(args, field.Name)
			if field.Value != "" {
				query.WriteString(fmt.Sprintf("AND cf%d.value = ? ", i))
				args = append(args, field.Value)
			}
		}
		if _, err := s.dbWrite.ExecContext(ctx, query.String(), args...); err != nil {
			return errors.Wrap(err, "deleting")
		}
		return nil
	}))
	return err
}

func (s *storage) GetMatchingEntries(ctx context.Context, potentialRecipients []int64, reasons []string, msgMatchFields notify.MessageMatchFields) ([]*matchengine.MatchedEntry, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	return mysql.WithRetries(ctx, s.clock, s.telem, func(c context.Context) ([]*matchengine.MatchedEntry, error) {
		var ret []*matchengine.MatchedEntry

		if len(potentialRecipients) == 0 {
			return []*matchengine.MatchedEntry{}, nil
		}

		query, parameters, err := buildMatchingRoutingSettingsQuery(
			potentialRecipients,
			reasons,
			msgMatchFields.Topics,
			msgMatchFields.SubjectType,
			msgMatchFields.Trigger,
			msgMatchFields.Attributes...,
		)
		if err != nil {
			return nil, err
		}

		if err := s.dbRead.SelectContext(ctx, &ret, query, parameters...); err != nil {
			return nil, err
		}
		return ret, nil
	})
}

func (s *storage) GetChannels(ctx context.Context, routingSettingIDs []int64) (map[int64][]matchengine_dto.Channel, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	return mysql.WithRetries(ctx, s.clock, s.telem, func(c context.Context) (map[int64][]matchengine_dto.Channel, error) {
		channelsByRoutingSettingID := make(map[int64][]matchengine_dto.Channel)
		var ret []*matchengine_dto.Channel

		if len(routingSettingIDs) == 0 {
			return channelsByRoutingSettingID, nil
		}

		sql, args, err := squirrel.Select("*").From("routing_setting_channels").Where(squirrel.Eq{"routing_setting_id": routingSettingIDs}).ToSql()
		if err != nil {
			return nil, err
		}

		if err := s.dbRead.SelectContext(ctx, &ret, sql, args...); err != nil {
			return nil, err
		}

		channelsByRoutingSettingID = matchengine_dto.MapChannelsByRoutingSettingID(ret)

		return channelsByRoutingSettingID, nil
	})
}

func (s *storage) deleteInTx(ctx context.Context, txx *sqlx.Tx, metaRoutingSettingIDs []int64) error {
	if len(metaRoutingSettingIDs) == 0 {
		return nil
	}

	routingSettingIDs, err := s.getRoutingIDsByMetaRoutingSettingIDs(ctx, metaRoutingSettingIDs)
	if err != nil {
		return err
	}

	if len(routingSettingIDs) == 0 {
		return nil
	}

	err = deleteByRoutingSettingIDsInTX(ctx, txx, "routing_setting_match_rules", routingSettingIDs)
	if err != nil {
		return errors.Wrap(err, "deleteInTx failed")
	}

	err = deleteByRoutingSettingIDsInTX(ctx, txx, "routing_setting_channels", routingSettingIDs)
	if err != nil {
		return errors.Wrap(err, "deleteInTx failed")
	}

	err = deleteByIDsInTx(ctx, txx, "routing_settings", routingSettingIDs)
	if err != nil {
		return errors.Wrap(err, "deleteInTx failed")
	}

	err = deleteByIDsInTx(ctx, txx, "meta_routing_settings", metaRoutingSettingIDs)
	if err != nil {
		return errors.Wrap(err, "deleteInTx failed")
	}

	err = deleteByMetaIDsInTx(ctx, txx, "routing_setting_custom_fields", metaRoutingSettingIDs)
	if err != nil {
		return errors.Wrap(err, "deleteInTx failed")
	}

	return nil
}

func buildMatchingRoutingSettingsQuery(potentialRecipients []int64, reasons []string, topics []notify.Topic, subject, trigger string, notifyMsgAttributes ...notify.Attribute) (string, []interface{}, error) {
	recipientFilter := squirrel.Eq{"routing_settings.user_id": potentialRecipients}

	subquery := squirrel.Select("routing_settings.id", "user_id", "reason").From("routing_settings").
		LeftJoin(
			"routing_setting_match_rules ON routing_settings.id = `routing_setting_match_rules`.routing_setting_id ").
		Where(recipientFilter)

	if len(reasons) > 0 {
		subquery = subquery.Where(squirrel.Or{
			squirrel.Eq{"routing_settings.reason": "any"},
			squirrel.Eq{"routing_settings.reason": reasons},
		})
	}

	// we need any/any combination of topic_type and topic_value to support global routing settings use-case
	// instead of topic we will rely on reason or subject fields
	topicsFilter := squirrel.Or{
		squirrel.And{
			squirrel.Eq{"routing_settings.topic_type": "any"},
			squirrel.Eq{"routing_settings.topic_value": "any"},
		},
	}
	for _, topic := range topics {
		condition := squirrel.And{
			squirrel.Eq{"routing_settings.topic_type": topic.Type},
			squirrel.Eq{"routing_settings.topic_value": topic.Value},
		}
		topicsFilter = append(topicsFilter, condition)
	}

	// we need all 3 combination of subject type + trigger to match generic subscriptions that don't specify some or either of those 2 fields.
	// for example:
	// - I want to get all notifications from GitHub/GitHub vs
	// - I want to get all Issues create notifications from GitHub/GitHub
	// in both cases we will need to match subscriptions
	subjectAndTriggerFilter := squirrel.Or{
		squirrel.And{squirrel.Eq{"routing_settings.subject_type": "any"}, squirrel.Eq{"routing_settings.trigger": "any"}},
		squirrel.And{squirrel.Eq{"routing_settings.subject_type": subject}, squirrel.Eq{"routing_settings.trigger": "any"}},
		squirrel.And{squirrel.Eq{"routing_settings.subject_type": subject}, squirrel.Eq{"routing_settings.trigger": trigger}},
	}

	// we need this to include routing settings with no match_rules
	matchRulesFilter := squirrel.Or{mysqlquery.IsNull("routing_setting_match_rules.routing_setting_id")}
	for _, notifyMsgAttr := range notifyMsgAttributes {
		expr := squirrel.And{
			squirrel.Eq{"routing_setting_match_rules.attribute": notifyMsgAttr.Name},
			squirrel.Or{
				squirrel.Eq{"routing_setting_match_rules.value": notifyMsgAttr.Value},
				squirrel.NotEq{"routing_setting_match_rules.match": "eq"},
			},
		}

		matchRulesFilter = append(matchRulesFilter, expr)
	}

	subquery = subquery.
		Where(topicsFilter).
		Where(subjectAndTriggerFilter).
		Where(matchRulesFilter)

	// we need this query because it will select all match_rules that belong to subscription.
	// It will be used for in-memory filtering. Otherwise, we will select only rules that have matched query to DB.
	query := squirrel.
		Select(
			"pre_selected_query.id AS ref_id",
			"pre_selected_query.user_id",
			"pre_selected_query.reason",
			"routing_setting_match_rules.attribute",
			"routing_setting_match_rules.value",
			"routing_setting_match_rules.`match` AS match_rule",
		).
		FromSelect(subquery, "pre_selected_query").
		LeftJoin("routing_setting_match_rules ON pre_selected_query.id = `routing_setting_match_rules`.routing_setting_id")

	return query.ToSql()
}

// used in tests only
func (s *storage) getRoutingSettings(ctx context.Context, userID int64) ([]*Setting, error) {
	sql, args, err := squirrel.Select("*").From("routing_settings").Where(squirrel.Eq{"user_id": userID}).ToSql()
	if err != nil {
		return []*Setting{}, errors.Wrap(err, "failed to build SQL query to fetch routing settings")
	}

	var routingSettings []*Setting
	if err := s.dbRead.SelectContext(ctx, &routingSettings, sql, args...); err != nil {
		return []*Setting{}, errors.Wrap(err, "Unable to fetch routing settings")
	}

	if len(routingSettings) == 0 {
		return routingSettings, nil
	}

	routingSettingsToIDsMap := map[int64]*Setting{}
	var id []int64
	for _, item := range routingSettings {
		id = append(id, item.ID)
		routingSettingsToIDsMap[item.ID] = item
	}

	matchRules, err := s.getMatchRulesByRoutingSettingIDs(ctx, id)
	if err != nil {
		return nil, err
	}

	channels, err := s.getChannelsByRoutingSettingIDs(ctx, id)
	if err != nil {
		return nil, err
	}

	for _, matchRule := range matchRules {
		routingSettingsToIDsMap[matchRule.RoutingSettingID].MatchRules = append(routingSettingsToIDsMap[matchRule.RoutingSettingID].MatchRules, matchRule)
	}

	for _, channel := range channels {
		if len(routingSettingsToIDsMap[channel.RoutingSettingID].Channels) == 0 {
			routingSettingsToIDsMap[channel.RoutingSettingID].Channels = make(map[string]*matchengine_dto.Channel)
		}

		c := channel
		routingSettingsToIDsMap[channel.RoutingSettingID].Channels[channel.Channel] = &c
	}

	var routingSettingsWithMatchRulesAndChannels []*Setting
	for _, routingSetting := range routingSettingsToIDsMap {
		routingSettingsWithMatchRulesAndChannels = append(routingSettingsWithMatchRulesAndChannels, routingSetting)
	}

	return routingSettingsWithMatchRulesAndChannels, nil
}

func (s *storage) getMatchRulesByRoutingSettingIDs(ctx context.Context, ids []int64) ([]SettingMatchRule, error) {
	sql, args, err := squirrel.Select("*").From("routing_setting_match_rules").Where(squirrel.Eq{"routing_setting_id": ids}).ToSql()
	if err != nil {
		return nil, errors.Wrap(err, "error building select match rules query")
	}

	var matchRules []SettingMatchRule
	if err := s.dbRead.SelectContext(ctx, &matchRules, sql, args...); err != nil {
		return nil, errors.Wrap(err, "error executing select match rules query")
	}

	return matchRules, nil
}

func (s *storage) getChannelsByRoutingSettingIDs(ctx context.Context, ids []int64) ([]matchengine_dto.Channel, error) {
	sql, args, err := squirrel.Select("*").From("routing_setting_channels").Where(squirrel.Eq{"routing_setting_id": ids}).ToSql()
	if err != nil {
		return nil, errors.Wrap(err, "error building select channels query")
	}

	var channels []matchengine_dto.Channel
	if err := s.dbRead.SelectContext(ctx, &channels, sql, args...); err != nil {
		return nil, errors.Wrap(err, "error executing select channels query")
	}

	return channels, nil
}

func (s *storage) getMetaRoutingSettingByID(ctx context.Context, id int64) (*MetaSetting, error) {
	sql, args, err := squirrel.Select("*").From("meta_routing_settings").Where(squirrel.Eq{"id": id}).ToSql()
	if err != nil {
		return nil, errors.Wrap(err, "error building select meta routing settings query")
	}

	var metaRoutingSettingSlice []*MetaSetting
	if err := s.dbRead.SelectContext(ctx, &metaRoutingSettingSlice, sql, args...); err != nil {
		return nil, errors.Wrap(err, "Unable to fetch meta routing settings")
	}

	if len(metaRoutingSettingSlice) == 0 {
		return &MetaSetting{}, nil
	}

	if len(metaRoutingSettingSlice) > 1 {
		return nil, errors.New("found more than one meta routing setting by id")
	}

	return metaRoutingSettingSlice[0], nil
}

// GetSettings returns routing settings, optionally filtered by custom fields
func (s *storage) GetSettings(ctx context.Context, fields []CustomField, page pagination.Page) ([]*MetaSetting, pagination.Pages, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	settings, err := mysql.WithRetries(ctx, s.clock, s.telem, func(c context.Context) ([]*MetaSetting, error) {
		query, params, err := findQuery(nil, fields, page)
		if err != nil {
			return nil, errors.Wrap(err, "Unable to build query for fetching meta routing setting")
		}

		var settings []*MetaSetting
		if err := s.dbRead.SelectContext(ctx, &settings, query, params...); err != nil {
			return nil, errors.Wrap(err, "Unable to fetch meta routing setting")
		}

		return settings, nil
	})

	if err != nil {
		return nil, pagination.NewEmptyStandardPages(), err
	}

	if len(settings) == int(page.Limit()) {
		lastID := strconv.FormatInt(settings[len(settings)-1].ID, 10)
		return settings, pagination.NewStandardPages(pagination.EncodeV1Cursor(lastID)), nil
	}

	return settings, pagination.NewEmptyStandardPages(), nil
}

// GetSettingsForUsers returns routing settings for a set of users, optionally filtered by custom fields
func (s *storage) GetSettingsForUsers(ctx context.Context, userIDs []int64, fields []CustomField, page pagination.Page) ([]*MetaSetting, pagination.Pages, error) {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	settings, err := mysql.WithRetries(ctx, s.clock, s.telem, func(c context.Context) ([]*MetaSetting, error) {
		query, params, err := findQuery(userIDs, fields, page)
		if err != nil {
			return nil, errors.Wrap(err, "Unable to build query for fetching meta routing setting")
		}

		var settings []*MetaSetting
		if err := s.dbRead.SelectContext(ctx, &settings, query, params...); err != nil {
			return nil, errors.Wrap(err, "Unable to fetch meta routing setting")
		}

		return settings, nil
	})

	if err != nil {
		return nil, pagination.NewEmptyStandardPages(), err
	}

	if len(settings) == int(page.Limit()) {
		lastID := strconv.FormatInt(settings[len(settings)-1].ID, 10)
		return settings, pagination.NewStandardPages(pagination.EncodeV1Cursor(lastID)), nil
	}

	return settings, pagination.NewEmptyStandardPages(), nil
}

func findQuery(userIDs []int64, fields []CustomField, page pagination.Page) (string, []interface{}, error) {
	query := squirrel.Select(
		"rs.id AS id",
		"rs.user_id AS user_id",
		"rs.name AS name",
		"rs.details AS details",
		"rs.updated_at AS updated_at",
		"rs.created_at AS created_at",
	).From("meta_routing_settings AS rs")
	for i := range fields {
		query = query.Join(fmt.Sprintf("routing_setting_custom_fields AS cf%d ON rs.id = `cf%d`.meta_id AND rs.user_id = `cf%d`.user_id", i, i, i))
	}
	var filter squirrel.And
	for i, field := range fields {
		filter = append(filter, squirrel.Eq{fmt.Sprintf("cf%d.name", i): field.Name})
		if field.Value != "" {
			filter = append(filter, squirrel.Eq{fmt.Sprintf("cf%d.value", i): field.Value})
		}
	}
	if len(userIDs) > 0 {
		filter = append(filter, squirrel.Eq{"rs.user_id": userIDs})
	}
	query = query.Where(filter)
	query = page.ApplyToAnyQuery(query, applyCursorQuery, applyOrderBy, applyLimit)
	return query.ToSql()
}

func createMetaRoutingSettingInTx(ctx context.Context, clock clockpkg.Clock, txx *sqlx.Tx, metaRoutingSetting *MetaSetting) (*MetaSetting, error) {
	metaRoutingSetting.UpdateTimestamps(clock)
	sql, args, err := squirrel.Insert("meta_routing_settings").
		Columns("user_id", "name", "details", "created_at", "updated_at").
		Values(
			metaRoutingSetting.UserID,
			metaRoutingSetting.Name,
			metaRoutingSetting.Details,
			metaRoutingSetting.CreatedAt,
			metaRoutingSetting.UpdatedAt,
		).
		ToSql()

	if err != nil {
		return nil, errors.Wrap(err, "create routing setting SQL failed")
	}

	sqlResult, err := txx.ExecContext(ctx, sql, args...)
	if err != nil {
		return nil, errors.Wrap(err, "create routing setting failed")
	}

	id, err := sqlResult.LastInsertId()
	if err != nil {
		return nil, err
	}

	metaRoutingSetting.ID = id

	if err := saveCustomFieldsInTx(ctx, clock, txx, metaRoutingSetting); err != nil {
		return nil, errors.Wrap(err, "saving custom fields for routing settings failed")
	}

	return metaRoutingSetting, nil
}

func saveCustomFieldsInTx(ctx context.Context, clock clockpkg.Clock, txx *sqlx.Tx, metaRoutingSetting *MetaSetting) error {
	if len(metaRoutingSetting.Details.CustomFields) == 0 {
		return nil
	}

	insert := squirrel.Insert("routing_setting_custom_fields").
		Columns("user_id", "meta_id", "name", "value", "created_at", "updated_at")

	for i := range metaRoutingSetting.Details.CustomFields {
		var field sqlCustomField
		field.Name = metaRoutingSetting.Details.CustomFields[i].Name
		field.Value = metaRoutingSetting.Details.CustomFields[i].Value
		field.UserID = metaRoutingSetting.UserID
		field.RoutingSettingID = metaRoutingSetting.ID
		field.UpdateTimestamps(clock)

		insert = insert.Values(
			field.UserID,
			field.RoutingSettingID,
			field.Name,
			field.Value,
			field.CreatedAt,
			field.UpdatedAt,
		)
	}

	sql, args, err := insert.ToSql()
	if err != nil {
		return err
	}

	if _, err := txx.ExecContext(ctx, sql, args...); err != nil {
		return err
	}

	return nil
}

func createRoutingSettingsInTx(ctx context.Context, txx *sqlx.Tx, clock clockpkg.Clock, routingSettings []*Setting) ([]*Setting, error) {
	if len(routingSettings) == 0 {
		return []*Setting{}, nil
	}

	var savedRoutingSettings []*Setting

	for _, rs := range routingSettings {
		sql, args, err := squirrel.Insert("routing_settings").
			Columns(
				"user_id",
				"topic_type",
				"topic_value",
				"subject_type",
				"routing_settings.trigger",
				"reason",
				"notify",
				"meta_id",
				"created_at",
				"updated_at",
			).
			Values(
				rs.UserID,
				rs.TopicType,
				rs.TopicValue,
				rs.SubjectType,
				rs.Trigger,
				rs.Reason,
				rs.Notify,
				rs.MetaID,
				rs.CreatedAt,
				rs.UpdatedAt,
			).
			ToSql()
		if err != nil {
			return []*Setting{}, errors.Wrap(err, "create routing setting SQL failed")
		}

		sqlResult, err := txx.ExecContext(ctx, sql, args...)
		if err != nil {
			return []*Setting{}, errors.Wrap(err, "create routing setting failed")
		}

		id, err := sqlResult.LastInsertId()
		if err != nil {
			return []*Setting{}, err
		}

		rs.ID = id
		if err := saveMatchRulesInTx(ctx, txx, clock, rs); err != nil {
			return []*Setting{}, errors.Wrap(err, "saving match rules for routing setting failed")
		}

		if err := saveChannelsInTx(ctx, txx, clock, rs); err != nil {
			return nil, errors.Wrap(err, "create routing settings channels failed")
		}

		savedRoutingSettings = append(savedRoutingSettings, rs)
	}

	return savedRoutingSettings, nil
}

func saveMatchRulesInTx(ctx context.Context, txx *sqlx.Tx, clock clockpkg.Clock, routingSetting *Setting) error {
	if len(routingSetting.MatchRules) == 0 {
		return nil
	}

	insert := squirrel.Insert("routing_setting_match_rules").
		Columns("routing_setting_id", "attribute", "value", "`match`", "created_at", "updated_at")

	for idx := range routingSetting.MatchRules {
		rule := &routingSetting.MatchRules[idx]
		rule.RoutingSettingID = routingSetting.ID
		rule.UpdateTimestamps(clock)

		insert = insert.Values(
			rule.RoutingSettingID,
			rule.Attribute,
			rule.Value,
			rule.MatchRule,
			rule.CreatedAt,
			rule.UpdatedAt,
		)
	}

	sql, args, err := insert.ToSql()
	if err != nil {
		return err
	}

	if _, err := txx.ExecContext(ctx, sql, args...); err != nil {
		return err
	}

	return nil
}

func (s *storage) getRoutingIDsByMetaRoutingSettingIDs(ctx context.Context, ids []int64) ([]int64, error) {
	sql, args, err := squirrel.Select("id").From("routing_settings").Where(squirrel.Eq{"meta_id": ids}).ToSql()
	if err != nil {
		return nil, err
	}

	var routingIDs []int64
	if err := s.dbRead.SelectContext(ctx, &routingIDs, sql, args...); err != nil {
		return nil, err
	}

	return routingIDs, nil
}

func deleteByMetaIDsInTx(ctx context.Context, txx *sqlx.Tx, table string, metaRoutingSettingIDs []int64) error {
	sql, args, err := squirrel.Delete(table).Where(squirrel.Eq{"meta_id": metaRoutingSettingIDs}).ToSql()
	if err != nil {
		return errors.Wrapf(err, "error bulding delete %s query", table)
	}

	if _, err := txx.ExecContext(ctx, sql, args...); err != nil {
		return errors.Wrapf(err, "delete %s failed", table)
	}

	return nil
}

func deleteByIDsInTx(ctx context.Context, txx *sqlx.Tx, table string, ids []int64) error {
	sql, args, err := squirrel.Delete(table).Where(squirrel.Eq{"id": ids}).ToSql()
	if err != nil {
		return errors.Wrapf(err, "error bulding delete %s query", table)
	}

	if _, err := txx.ExecContext(ctx, sql, args...); err != nil {
		return errors.Wrapf(err, "delete %s failed", table)
	}

	return nil
}

func deleteByRoutingSettingIDsInTX(ctx context.Context, txx *sqlx.Tx, table string, routingSettingIDs []int64) error {
	sql, args, err := squirrel.Delete(table).Where(squirrel.Eq{"routing_setting_id": routingSettingIDs}).ToSql()
	if err != nil {
		return errors.Wrapf(err, "error bulding delete %s query", table)
	}

	if _, err := txx.ExecContext(ctx, sql, args...); err != nil {
		return errors.Wrapf(err, "delete %s failed", table)
	}

	return nil
}

func (s *storage) deleteByCustomFieldsInTx(ctx context.Context, txx *sqlx.Tx, userID int64, fields []CustomField) error {
	// Should not delete all a user's routingSettings if no custom fields given
	if len(fields) == 0 {
		return nil
	}

	routingSettings, _, err := s.GetSettingsForUsers(ctx, []int64{userID}, fields, pagination.NewNoLimitPage())
	if err != nil {
		return errors.Wrap(err, "failed to fetch routingSettings by custom fields")
	}

	settingIDsToDelete := make([]int64, len(routingSettings))
	for idx, subscription := range routingSettings {
		settingIDsToDelete[idx] = subscription.ID
	}

	err = s.deleteInTx(ctx, txx, settingIDsToDelete)
	if err != nil {
		return errors.Wrap(err, "failed to delete routingSettings")
	}

	return nil
}

func applyCursorQuery(query squirrel.SelectBuilder, page pagination.Page) squirrel.SelectBuilder {
	stringID := pagination.DecodeCursor(page.Cursor())
	id, _ := strconv.ParseInt(stringID, 10, 64)

	// if we have a cursor, add it as a where clause
	if id > 0 {
		query = query.Where(squirrel.Gt{paginationID: id})
	}
	return query
}

func applyOrderBy(query squirrel.SelectBuilder, page pagination.Page) squirrel.SelectBuilder {
	// cursor-based pagination requires an order by clause
	return query.OrderBy(paginationID + " ASC")
}

func applyLimit(query squirrel.SelectBuilder, page pagination.Page) squirrel.SelectBuilder {
	// if we have a limit, set it or fallback to the upper limit
	if page.Limit() > 0 {
		return query.Suffix("LIMIT ?", int(min(page.Limit(), MaximumRequestPageLimit)))
	}
	return query.Suffix("LIMIT ?", MaximumRequestPageLimit)
}
