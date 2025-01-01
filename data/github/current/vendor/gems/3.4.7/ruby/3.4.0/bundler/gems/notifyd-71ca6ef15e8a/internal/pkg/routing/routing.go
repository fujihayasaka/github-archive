package routing

import (
	"bytes"
	"context"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/telemetry"
	"github.com/github/go-stats"

	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/featureflags"
	"github.com/github/notifyd/internal/pkg/notify"
	"github.com/github/notifyd/internal/pkg/notify/matchengine"
	matchengine_dto "github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/o11y"
)

// Service offers an API to retrieve delivery data to route notifications.
type Service interface {
	GetDeliveryMetadata(ctx context.Context, recipients notify.RecipientIDToReasons, query *MatchQuery) notify.RecipientToDeliveryMetadata
}

type routingService struct {
	storage            Storage
	telem              *telemetry.Provider
	statter            stats.Client
	featureFlagsClient featureflags.Client
}

// NewRoutingService builds a new routing service.
func NewRoutingService(storage Storage, telem *telemetry.Provider, statter stats.Client, features featureflags.Client) Service {
	return routingService{
		storage:            storage,
		telem:              telem,
		statter:            statter,
		featureFlagsClient: features,
	}
}
func (s routingService) GetDeliveryMetadata(ctx context.Context, recipients notify.RecipientIDToReasons, query *MatchQuery) notify.RecipientToDeliveryMetadata {
	t0 := time.Now()
	defer func() {
		s.statter.DistributionMs("routing_settings.get_delivery_metadata.time", stats.Tags{}, time.Since(t0))
	}()
	return s.getDeliveryMetadata(ctx, recipients, query)
}

func (s routingService) getDeliveryMetadata(ctx context.Context, recipients notify.RecipientIDToReasons, query *MatchQuery) notify.RecipientToDeliveryMetadata {
	ctx = o11y.CtxSetPackage(ctx, "routing")
	ctx = o11y.CtxSetMethod(ctx, "getdeliverymetadata")

	flags := s.fetchFeatureFlags(ctx, recipients)

	// TODO: mobile-auth-requests are a special case that should be handled via a special endpoint
	if strings.HasPrefix(query.notificationID, "mobile-auth-request/user-") {
		return s.defaultDeliveryMetadata(query.fields, recipients, flags)
	}

	matchingRoutingSettingsPerRecipient, err := s.getMatchingSettingsPerRecipients(ctx, recipients, query)

	if err != nil {
		s.telem.Logger.WithContext(ctx).WithError(err).Info("Unable to apply stored routing setting, falling back to defaults")
		return s.defaultDeliveryMetadata(query.fields, recipients, flags)
	}

	recipientToDeliveryMetadata := make(notify.RecipientToDeliveryMetadata)
	for recipientID, reasons := range recipients {
		ctx = o11y.CtxSetUserID(ctx, recipientID) //nolint:fatcontext // UserID is overwritten for each recipient
		logger := s.telem.Logger.WithContext(ctx).WithFields(kvp.String("gh.notifyd.featureflags", featureFlagsToString(flags[recipientID])))

		channels := make(matchengine_dto.ChannelsMap)

		// at first, we need to apply default settings because they are going to be overwritten
		// by any specific routing settings matched by user
		applyDefaultSettingsToChannels(query.fields, reasons, channels)
		applyDefaultDynamicSettingsToChannels(recipientID, query.fields, reasons, channels)
		applyDefaultFeatureFlagsSettingsToChannels(flags[recipientID], query.fields, reasons, channels)

		logger.WithFields(kvp.String("gh.notifyd.channels", channelsToString(channels))).Info("applying default channels")

		routingSettingsMatchEntries, exists := matchingRoutingSettingsPerRecipient[recipientID]
		if exists {
			// we also put negative rules over positive rules for now
			// if there are 2 conflicting rules, negative always wins

			// apply enabled channelsToNotifyUser first
			channels = s.applyStoredEnabledChannels(routingSettingsMatchEntries, reasons, channels)
			logger.WithFields(kvp.String("gh.notifyd.channels", channelsToString(channels))).Info("applying enabled channels")

			// apply disabled channelsToNotifyUser on top, they will override enabled channelsToNotifyUser
			channels = s.applyStoredDisabledChannels(routingSettingsMatchEntries, reasons, channels)
			logger.WithFields(kvp.String("gh.notifyd.channels", channelsToString(channels))).Info("applying disabled channels")
		}

		logger.WithFields(
			kvp.String("gh.notifyd.channels", channelsToString(channels)),
			kvp.String("gh.notifyd.reasons", strings.Join(reasons, ", ")),
		).
			Info("applied stored routing settings")

		applyDisabledFeatureFlagsSettingsToChannels(flags[recipientID], query.fields, reasons, channels)
		logger.WithFields(
			kvp.String("gh.notifyd.channels", channelsToString(channels)),
			kvp.String("gh.notifyd.reasons", strings.Join(reasons, ", ")),
		).Info("final routing settings")

		s.reportRoutingSettingsStats(channels)

		recipientToDeliveryMetadata[recipientID] = notify.DeliveryMetadata{Channels: channels, Reasons: reasons}
	}

	return recipientToDeliveryMetadata
}

func (s routingService) defaultDeliveryMetadata(matchFields notify.MessageMatchFields, recipients notify.RecipientIDToReasons, recipientFeatureFlags map[int64][]featureFlag) notify.RecipientToDeliveryMetadata {
	recipientToDeliveryMetadata := make(notify.RecipientToDeliveryMetadata)
	for recipientID, reasons := range recipients {
		channels := make(matchengine_dto.ChannelsMap)
		applyDefaultSettingsToChannels(matchFields, reasons, channels)
		applyDefaultFeatureFlagsSettingsToChannels(recipientFeatureFlags[recipientID], matchFields, reasons, channels)

		recipientToDeliveryMetadata[recipientID] = notify.DeliveryMetadata{Channels: channels, Reasons: reasons}
	}

	return recipientToDeliveryMetadata
}

func (s routingService) applyStoredEnabledChannels(routingSettingsMatchEntries []*matchengine.MatchedEntry, reasons []string, channelsToNotify matchengine_dto.ChannelsMap) matchengine_dto.ChannelsMap {
	return s.applyStoredChannels(routingSettingsMatchEntries, reasons, channelsToNotify, true)
}

func (s routingService) applyStoredDisabledChannels(routingSettingsMatchEntries []*matchengine.MatchedEntry, reasons []string, channelsToNotify matchengine_dto.ChannelsMap) matchengine_dto.ChannelsMap {
	return s.applyStoredChannels(routingSettingsMatchEntries, reasons, channelsToNotify, false)
}

func (s routingService) applyStoredChannels(routingSettingsMatchEntries []*matchengine.MatchedEntry, reasons []string, channelsToNotify matchengine_dto.ChannelsMap, enabled bool) matchengine_dto.ChannelsMap {
	all := false
	for _, matchEntry := range routingSettingsMatchEntries {
		for channelName, channel := range matchEntry.Channels {
			if !reasonsForRecipientAreMatched(matchEntry.Reason, reasons) {
				continue
			}
			if channel.Enabled == enabled {
				if channelName == "ALL" {
					all = true
				} else {
					channelsToNotify[strings.ToUpper(channelName)] = channel
				}
			}
		}
	}
	if all {
		for name := range channelsToNotify {
			channelsToNotify[name].Enabled = enabled
		}
	}

	return channelsToNotify
}

type featureFlag struct {
	Name    string
	Enabled bool
}

func (s routingService) fetchFeatureFlags(ctx context.Context, recipients notify.RecipientIDToReasons) map[int64][]featureFlag {
	start := time.Now()

	// TODO(abeaumont): use maps.Keys instead once it's available.
	var recipientIDs []int64
	for recipientID := range recipients {
		recipientIDs = append(recipientIDs, recipientID)
	}

	features := make(map[string]map[string]bool)
	for feature := range recipientSettingsPerFeatureFlag {
		recipients, err := s.featureFlagsClient.IsEnabledForActors(ctx, feature, recipientIDs)
		if err != nil {
			s.telem.Logger.WithContext(ctx).WithError(err).WithFields(kvp.String("gh.notifyd.featureflag.name", feature)).
				Error("Error fetching delivery feature flag for recipients")
			continue
		}

		features[feature] = recipients
	}

	flags := make(map[int64][]featureFlag)
	for recipientID := range recipients {
		for flag, recipients := range features {
			if _, ok := flags[recipientID]; !ok {
				flags[recipientID] = []featureFlag{}
			}

			if enabled, ok := recipients[fmt.Sprintf("User:%d", recipientID)]; ok {
				flags[recipientID] = append(flags[recipientID], featureFlag{
					Name:    flag,
					Enabled: enabled,
				})
			}
		}
	}

	s.statter.DistributionMs("routing_settings.fetch_feature_flags_for_recipients", stats.Tags{}, time.Since(start))
	return flags
}

func reasonsForRecipientAreMatched(entryReason string, recipientReasons []string) bool {
	return entryReason == "" || entryReason == "any" || contains(recipientReasons, entryReason)
}

func extractRecipientsAndReasons(recipients notify.RecipientIDToReasons) ([]int64, []string) {
	recipientIDs := make([]int64, 0, len(recipients))
	reasonsMap := make(map[string]bool)
	for userID, reasons := range recipients {
		recipientIDs = append(recipientIDs, userID)
		for _, r := range reasons {
			reasonsMap[r] = true
		}
	}

	var reasons []string
	for r := range reasonsMap {
		reasons = append(reasons, r)
	}

	return recipientIDs, reasons
}

func channelsToString(channels matchengine_dto.ChannelsMap) string {
	keys := make([]string, 0, len(channels))
	for channel := range channels {
		keys = append(keys, channel)
	}
	sort.Strings(keys)

	var buffer bytes.Buffer
	var sep string
	for _, key := range keys {
		_, _ = buffer.WriteString(sep)
		channel := channels[key]
		if _, err := buffer.WriteString(fmt.Sprintf("%s: %t", key, channel.Enabled)); err != nil {
			return ""
		}
		sep = ", "
	}
	return buffer.String()
}

func (s routingService) reportRoutingSettingsStats(channels matchengine_dto.ChannelsMap) {
	for _, channel := range channels {
		if channel != nil {
			s.statter.Counter("routing_settings.decision", stats.Tags{"channel": channel.Channel, "enabled": strconv.FormatBool(channel.Enabled)}, 1)
		}
	}

	if len(channels) == 0 {
		s.statter.Counter("routing_settings.decision", stats.Tags{"channel": "none", "enabled": "false"}, 1)
	}
}

func applyDisabledFeatureFlagsSettingsToChannels(recipientFlags []featureFlag, matchFields notify.MessageMatchFields, reasons []string, channels matchengine_dto.ChannelsMap) {
	for _, featureFlag := range recipientFlags {
		if featureFlagSettings, ok := recipientSettingsPerFeatureFlag[featureFlag.Name]; ok && !featureFlag.Enabled {
			// Override the default and stored value if the feature flag is disabled
			matchAndApplySettingsWithChannelValue(featureFlagSettings, matchFields, reasons, channels, false)
		}
	}
}

// Convert a the sequence of actor and recipient feature flags into a string
func featureFlagsToString(flags []featureFlag) string {
	strs := make([]string, len(flags))
	for i, flag := range flags {
		strs[i] = fmt.Sprintf("%s (recipient): %t", flag.Name, flag.Enabled)
	}
	return strings.Join(strs, ", ")
}

func (s routingService) getMatchingSettingsPerRecipients(ctx context.Context, recipients notify.RecipientIDToReasons, query *MatchQuery) (map[int64][]*matchengine.MatchedEntry, error) {
	logger := s.telem.Logger.WithContext(ctx)

	if err := query.Matchable(); err != nil {
		return nil, err
	}

	recipientIDs, reasons := extractRecipientsAndReasons(recipients)
	matchingEntries, err := s.storage.GetMatchingEntries(ctx, recipientIDs, reasons, query.fields)
	if err != nil {
		logger.WithError(err).Error("Routing settings service: failed to get matching entries")
		return nil, errors.Wrap(err, "Routing settings service: failed to get matching entries")
	}

	settingIDSet := make(map[int64]struct{})
	for _, matchedEntry := range matchingEntries {
		settingIDSet[matchedEntry.RefID] = struct{}{}
	}

	settingIDs := make([]int64, 0, len(settingIDSet))
	for id := range settingIDSet {
		settingIDs = append(settingIDs, id)
	}

	if err := s.setChannels(ctx, matchingEntries, settingIDs); err != nil {
		return nil, err
	}

	var reasonGroups []notify.ReasonGroup
	if query != nil {
		reasonGroups = query.reasonGroups
	}
	matcher := matchengine.BuildMatcherForRoutingSettings(s.telem, query.fields.Attributes, recipients, reasonGroups)
	matcher.LoadMatchedEntries(matchingEntries)

	return matcher.MatchedRecipients(), nil
}

func (s routingService) setChannels(ctx context.Context, matchingEntries []*matchengine.MatchedEntry, settingIDs []int64) error {
	logger := s.telem.Logger.WithContext(ctx)
	channels, err := s.storage.GetChannels(ctx, settingIDs)
	if err != nil {
		logger.WithError(err).Error("Routing settings service: failed to get routing settings channels")
		return errors.Wrap(err, "Routing settings service: failed to get routing settings channels")
	}

	for _, matchedEntry := range matchingEntries {
		for _, channel := range channels[matchedEntry.RefID] {
			if matchedEntry.Channels == nil {
				matchedEntry.Channels = make(matchengine_dto.ChannelsMap)
			}

			matchedEntry.Channels[channel.Channel] = &channel
		}
	}
	return nil
}
