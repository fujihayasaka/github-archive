package newsiesservice

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	clockpkg "github.com/benbjohnson/clock"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/o11y/tracing"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
)

// Service represents the newsies service.
type Service struct {
	routingSvc       routing.SettingsService
	subscriptionsSvc subscriptions.Service
	statter          stats.Client
	clock            clockpkg.Clock
}

// NewService creates a new service.
func NewService(routingSvc routing.SettingsService,
	subscriptionsSvc subscriptions.Service,
	statter stats.Client,
	clock clockpkg.Clock) *Service {
	return &Service{routingSvc: routingSvc, subscriptionsSvc: subscriptionsSvc, statter: statter, clock: clock}
}

// ThreadType represents each one of the original thread types that a user can "watch" on newsies.
type ThreadType int

// ThreadType values.
const (
	Issue ThreadType = iota
	PullRequest
	Release
	Discussion
	SecurityAlert
)

// These constants are here so that we don't have "magic" strings spread and repeated all around the
// package.
const (
	// WatchActivityMatchRuleName match rules key names
	WatchActivityMatchRuleName    string = "watch_activity"
	ThreadTypeMatchRuleName       string = "thread_type"
	ThreadParticipantActivityName string = "thread_participant_activity"

	// WatchActivityMatchRuleValue match rules values
	WatchActivityMatchRuleValue    string = "true"
	ThreadParticipantActivityValue string = "true"

	// CategoryName CustomField key names
	CategoryName        string = "category"
	WatcherScenarioName string = "watcher_scenario"
	RepositoryIDName    string = "repository_id"
	OwnerTypeName       string = "owner_type"
	OwnerIDName         string = "owner_id"
	ThreadIDName        string = "thread_id"
	ThreadTypeName      string = "thread_type"
	LabelIDName         string = "label_id"

	// CategoryThreadTypeValue Custom field key values
	CategoryThreadTypeValue string = "thread_type"
	categoryAllValue        string = "all"
	CategoryThreadValue     string = "thread"
	watcherScenarioValue    string = "true"

	// ThreadTypeReason Reasons
	ThreadTypeReason string = "thread_type_subscription"
	ListReason       string = "list_subscription"

	// RepositoryRefType Expected ref type
	RepositoryRefType string = "repository"
)

// Watch creates a subscription for the given user in the given reference. This is based on the
// Watch flow of newsies and aims to operate in the same way.
//
// - Subscribe to all the activity on a given repo.
// - Subscribe to all the activity for a given set of thread types on a given repo.
//
// In the same sense, before the subscriptions are created all the existing ignores are cleaned.
func (s *Service) Watch(ctx context.Context,
	userID int64,
	refID int64,
	refType string,
	types []ThreadType,
	fields []subscriptions.CustomField) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	v := watchValidation(refType, fields)
	if !v.IsValid() {
		return v.ToError()
	}
	if err := s.cleanupIgnore(ctx, userID, refID); err != nil {
		return errors.Wrap(err, "cleaning up ignores")
	}

	if err := s.replaceSubscription(ctx, userID, refID, refType, types, fields); err != nil {
		return errors.Wrap(err, "upserting subscription")
	}

	return nil
}

// Unwatch removes any subscription that exist for the given reference (usually a Repository + its
// id).
//
// In addition to removing the subscription it cleans up ignores. Rather than an "Unwatch"
// operation, this is more like a "reset" operation, leaving the subscriptions for a repository in a
// default state. We use the name "Unwatch" instead because it is the one we use at newsies.
func (s *Service) Unwatch(ctx context.Context, userID int64, refIDs []int64, refType string) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	v := unwatchValidation(refType)
	if !v.IsValid() {
		return v.ToError()
	}

	for _, refID := range refIDs {
		if err := s.cleanupIgnore(ctx, userID, refID); err != nil {
			return errors.Wrap(err, fmt.Sprintf("cleaning up ignores for refID: %d", refID))
		}

		if err := s.cleanupSubscription(ctx, userID, refID); err != nil {
			return errors.Wrap(err, fmt.Sprintf("removing subscription for refID: %d", refID))
		}
	}

	return nil
}

// UnwatchAll removes any subscription that exist for the given reference type (usually a Repository)
//
// In addition to removing the subscription it cleans up ignores. Rather than an "Unwatch"
// operation, this is more like a "reset" operation, leaving the subscriptions for a repository in a
// default state. We use the name "Unwatch" instead because it is the one we use at newsies.
func (s *Service) UnwatchAll(ctx context.Context, userID int64, refType string) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	v := unwatchValidation(refType)
	if !v.IsValid() {
		return v.ToError()
	}

	if err := s.cleanupIgnore(ctx, userID, 0); err != nil {
		return errors.Wrap(err, "cleaning up all ignores")
	}

	if err := s.cleanupSubscription(ctx, userID, 0); err != nil {
		return errors.Wrap(err, "removing all watch subscriptions")
	}

	return nil
}

// Ignore will make sure that no notifications at all are sent to the given user on the given
// reference (usually Repository + id).
//
// It blocks all the activity coming from a given repository.
func (s *Service) Ignore(ctx context.Context,
	userID int64,
	refID int64,
	refType string,
	fields []routing.CustomField) error {
	ctx, span := tracing.StartSpanWithCaller(ctx)
	defer span.End()

	v := ignoreValidation(refType, fields)
	if !v.IsValid() {
		return v.ToError()
	}

	if err := s.replaceIgnore(ctx, userID, refID, refType, fields); err != nil {
		return errors.Wrap(err, "upserting ignore")
	}

	if err := s.cleanupSubscription(ctx, userID, refID); err != nil {
		return errors.Wrap(err, "removing subscription")
	}

	return nil
}

// replaceIgnore replaces any existing ignore for the matching subscriptions with a new one.
func (s *Service) replaceIgnore(ctx context.Context,
	userID int64,
	refID int64,
	refType string,
	fields []routing.CustomField) error {
	ignore := newIgnore(userID, refType, refID, fields)

	startTime := s.clock.Now()
	// We ignore the first return type because in this case BatchCreateAndDelete will add a new
	// setting and removing everything existing. The new setting will be an ignore.
	_, err := s.routingSvc.BatchReplace(ctx, userID, []*routing.MetaSetting{ignore}, ignoreQuery(refID))
	if err != nil {
		return err
	}
	s.statter.DistributionMs("notifyd.newsies_api.rsBatchReplace", stats.Tags{"action": "replace"}, s.clock.Since(startTime))

	return nil
}

// cleanupIgnore removes all the routing settings representing ignores for a given reference
// (usually a Repository + its ID)
func (s *Service) cleanupIgnore(ctx context.Context, userID, refID int64) error {
	startTime := s.clock.Now()
	// We ignore the first return type because in this case BatchCreateAndDelete will just remove all
	// the meta routing settings and none will be created.
	ignoreQuery := ignoreQuery(refID)
	_, err := s.routingSvc.BatchReplace(ctx, userID, []*routing.MetaSetting{}, ignoreQuery)
	if err != nil {
		return err
	}
	s.statter.DistributionMs("notifyd.newsies_api.rsBatchReplace", stats.Tags{"action": "replace"}, s.clock.Since(startTime))

	return nil
}

// ignoreQuery builds a slice of CustomField that is necessary to find the right routing
// settings that represent the current ignores.
func ignoreQuery(refID int64) []routing.CustomField {
	if refID > 0 {
		return []routing.CustomField{
			{Name: RepositoryIDName, Value: strconv.FormatInt(refID, 10)},
			{Name: WatcherScenarioName, Value: watcherScenarioValue},
		}
	}

	return []routing.CustomField{
		{Name: RepositoryIDName},
		{Name: WatcherScenarioName, Value: watcherScenarioValue},
	}
}

// replaceSubscription uses the given set of custom fields to insert a new subscription and replace
// the existing one if any.
func (s *Service) replaceSubscription(ctx context.Context,
	userID int64,
	refID int64,
	refType string,
	types []ThreadType,
	customFields []subscriptions.CustomField) error {
	startTime := s.clock.Now()
	subscription, err := newSubscription(userID, types, refID, refType, customFields)
	if err != nil {
		return err
	}

	query := watchQuery(refID)
	// NOTE: the ignored return value are the IDs of the newly created subscriptions.
	_, err = s.subscriptionsSvc.BatchReplace(ctx, userID, []*subscriptions.MetaSubscription{subscription}, query)
	if err != nil {
		return err
	}

	s.statter.DistributionMs("notifyd.newsies_api.replaceSubscriptions", stats.Tags{}, s.clock.Since(startTime))

	return nil
}

// cleanupSubscription cleans up existing subscriptions for a reference when we unwatch it.
func (s *Service) cleanupSubscription(ctx context.Context, userID, refID int64) error {
	startTime := s.clock.Now()
	// removing watch subscriptions
	query := watchQuery(refID)
	_, err := s.subscriptionsSvc.BatchReplace(ctx, userID, []*subscriptions.MetaSubscription{}, query)
	if err != nil {
		return err
	}
	s.statter.DistributionMs("notifyd.newsies_api.cleanupSubscription.watch", stats.Tags{}, s.clock.Since(startTime))

	// removing label subscriptions
	query = labelsQuery(refID)
	_, err = s.subscriptionsSvc.BatchReplace(ctx, userID, []*subscriptions.MetaSubscription{}, query)
	if err != nil {
		return err
	}
	s.statter.DistributionMs("notifyd.newsies_api.cleanupSubscription.labels", stats.Tags{}, s.clock.Since(startTime))

	return nil
}

// watchQuery builds a slice of custom fields that are used to query for the right
// subscription to replace.
func watchQuery(refID int64) []subscriptions.CustomField {
	if refID > 0 {
		return []subscriptions.CustomField{
			{Name: RepositoryIDName, Value: strconv.FormatInt(refID, 10)},
			{Name: WatcherScenarioName, Value: watcherScenarioValue},
		}
	}

	return []subscriptions.CustomField{
		{Name: RepositoryIDName},
		{Name: WatcherScenarioName, Value: watcherScenarioValue},
	}
}

// labelsQuery builds a slice of custom fields that are used to query for the right
// subscriptions to replace.
func labelsQuery(refID int64) []subscriptions.CustomField {
	if refID > 0 {
		return []subscriptions.CustomField{
			{Name: RepositoryIDName, Value: strconv.FormatInt(refID, 10)},
			{Name: LabelIDName},
		}
	}

	return []subscriptions.CustomField{
		{Name: RepositoryIDName},
		{Name: LabelIDName},
	}
}

// newSubscription builds a MetaSubscriptions that maps List and ThreadType subscriptions from
// newsies to the notifyd land.
func newSubscription(userID int64,
	types []ThreadType,
	refID int64,
	refType string,
	clientCustomFields []subscriptions.CustomField) (*subscriptions.MetaSubscription, error) {
	var builder subscriptionBuilder = listBuilder{
		refID:   refID,
		refType: refType,
	}
	if len(types) != 0 {
		builder = ThreadTypeBuilder{
			refID:   refID,
			refType: refType,
			types:   types,
		}
	}

	filters, err := builder.Filters()
	if err != nil {
		return nil, err
	}

	customFields, err := builder.CustomFields(clientCustomFields)
	if err != nil {
		return nil, err
	}

	return &subscriptions.MetaSubscription{
		UserID: userID,
		Name:   builder.Title(),
		Details: subscriptions.Details{
			Topics:       []subscriptions.Topic{{Type: strings.ToLower(refType), Value: strconv.FormatInt(refID, 10)}},
			Reason:       builder.Reason(),
			Filters:      filters,
			CustomFields: customFields,
		},
	}, nil
}

// newIgnore returns a MetaSetting configured to ignore a given reference (generally a
// repository).
//
// The routing setting configured has the following properties:
//
// - Uses the repository as the topics
// - Disables all the Channels for the matching messages
// - Sets up custom fields for the repository and a match rule for `Category:all`.
//
// Take into account that ignores are always repo-wide, so there's no such things as
// `Category:thread_type`
func newIgnore(userID int64, refType string, refID int64, fields []routing.CustomField) *routing.MetaSetting {
	builder := NewIgnoreBuilder(refID, refType)

	return &routing.MetaSetting{
		UserID: userID,
		Name:   builder.Title(),
		Details: routing.SettingDetails{
			Topics:       []routing.Topic{{Type: strings.ToLower(refType), Value: strconv.FormatInt(refID, 10)}},
			Filters:      builder.Filters(),
			Channels:     builder.Channels(),
			CustomFields: builder.CustomFields(fields),
		},
	}
}
