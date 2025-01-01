package routingsettingsserver

import (
	"strings"

	"github.com/github/notifyd/internal/pkg/mysql"
	"github.com/github/notifyd/internal/pkg/notify/matchengine/dto"
	"github.com/github/notifyd/internal/pkg/routing"
	pb "github.com/github/notifyd/proto/services/routingsettings"
)

// Functions to convert Protobuf to routing settings data types
func pbNewRoutingSettingToMetaSettings(userID int64, pbCreateRequest []*pb.Setting) []*routing.MetaSetting {
	settingsToCreate := make([]*routing.MetaSetting, len(pbCreateRequest))
	for idx, toCreate := range pbCreateRequest {
		settingsToCreate[idx] = &routing.MetaSetting{
			UserID: userID,
			Details: routing.SettingDetails{
				Filters:      pbToFilters(toCreate.Filters),
				Channels:     pbToChannels(toCreate.Channels),
				Topics:       pbToTopic(toCreate.Topics),
				CustomFields: pbToCustomFields(toCreate.CustomFields),
			},
		}
	}
	return settingsToCreate
}

func pbToMetaSettings(pbCreateRequest []*pb.CreateRequest) []*routing.MetaSetting {
	subscriptionsToCreate := make([]*routing.MetaSetting, len(pbCreateRequest))
	for idx, toCreate := range pbCreateRequest {
		subscriptionsToCreate[idx] = &routing.MetaSetting{
			UserID: int64(toCreate.UserId),
			Details: routing.SettingDetails{
				Filters:      pbToFilters(toCreate.Filters),
				Topics:       pbToTopic(toCreate.Topics),
				Channels:     pbToChannels(toCreate.Channels),
				CustomFields: pbToCustomFields(toCreate.CustomFields),
			},
		}
	}
	return subscriptionsToCreate
}

func pbToIDsToDelete(request *pb.BatchCreateAndDeleteRequest) []int64 {
	deletionIDs := make([]int64, len(request.ToDelete))
	for idx := range request.ToDelete {
		deletionIDs[idx] = request.ToDelete[idx].GetId()
	}
	return deletionIDs
}

func pbToSettingsToCreate(request *pb.BatchCreateAndDeleteRequest, ts mysql.Timestamps) []*routing.MetaSetting {
	creationSettings := make([]*routing.MetaSetting, len(request.ToCreate))
	for idx := range request.ToCreate {
		cr := request.ToCreate[idx]
		creationSettings[idx] = &routing.MetaSetting{
			UserID: int64(cr.UserId),
			Name:   cr.Name,
			Details: routing.SettingDetails{
				Channels:     pbToChannels(cr.Channels),
				Filters:      pbToFilters(cr.Filters),
				Topics:       pbToTopics(cr.Topics),
				CustomFields: pbToCustomFields(cr.CustomFields),
			},
			Timestamps: ts,
		}
	}
	return creationSettings
}

func pbToCustomFields(requestCustomField []*pb.CustomField) []routing.CustomField {
	var customFields = make([]routing.CustomField, len(requestCustomField))

	for idx, field := range requestCustomField {
		customFields[idx] = routing.CustomField{
			Name:  field.Name,
			Value: field.Value,
		}
	}

	return customFields
}

func pbToChannels(channels []*pb.Channel) map[string]*dto.Channel {
	result := make(map[string]*dto.Channel)
	for _, c := range channels {
		result[c.Name] = &dto.Channel{
			Channel: strings.ToUpper(c.Name),
			Enabled: c.Enabled,
		}
	}
	return result
}

func pbToFilters(filters []*pb.Filter) []routing.SettingFilter {
	result := make([]routing.SettingFilter, len(filters))
	for i, f := range filters {
		result[i] = routing.SettingFilter{
			Reason:      f.Reason,
			SubjectType: f.SubjectType,
			Trigger:     f.Trigger,
			MatchRules:  pbToMatchRules(f.MatchRules),
		}
	}
	return result
}

func pbToMatchRules(matchRules []*pb.MatchRule) []routing.SettingMatchRule {
	result := make([]routing.SettingMatchRule, len(matchRules))
	for i, m := range matchRules {
		result[i] = routing.SettingMatchRule{
			Attribute: m.Attribute,
			Value:     m.Value,
			MatchRule: m.MatchRule,
		}
	}
	return result
}

func pbToTopics(topics []*pb.Topic) []routing.Topic {
	result := make([]routing.Topic, len(topics))
	for i, t := range topics {
		result[i] = routing.Topic{
			Type:  t.Type,
			Value: t.Value,
		}
	}
	return result
}

// Functions to convert routing settings data types to Protobuf

func routingSettingToPB(rs *routing.MetaSetting) *pb.RoutingSetting {
	return &pb.RoutingSetting{
		Id: rs.ID,
		//nolint:gosec // Known issue https://github.com/github/notifyd/issues/3113
		UserId:       int32(rs.UserID),
		Name:         rs.Name,
		Channels:     channelsToPB(rs.Details.Channels),
		Topics:       topicsToPB(rs.Details.Topics),
		Filters:      filtersToPB(rs.Details.Filters),
		CustomFields: customFieldsToPB(rs.Details.CustomFields),
		CreatedAt:    rs.CreatedAt.Unix(),
	}
}

func channelsToPB(rsChannels map[string]*dto.Channel) []*pb.Channel {
	pbChannels := make([]*pb.Channel, 0, len(rsChannels))
	for name, channel := range rsChannels {
		pbChannels = append(pbChannels, &pb.Channel{
			Name:    name,
			Enabled: channel.Enabled,
		})
	}
	return pbChannels
}

func topicsToPB(rsTopics []routing.Topic) []*pb.Topic {
	pbTopics := make([]*pb.Topic, len(rsTopics))
	for i := range rsTopics {
		pbTopics[i] = &pb.Topic{
			Type:  rsTopics[i].Type,
			Value: rsTopics[i].Value,
		}
	}
	return pbTopics
}

func filtersToPB(rsFilters []routing.SettingFilter) []*pb.Filter {
	pbFilters := make([]*pb.Filter, len(rsFilters))
	for i := range rsFilters {
		pbFilters[i] = &pb.Filter{
			SubjectType: rsFilters[i].SubjectType,
			Trigger:     rsFilters[i].Trigger,
			Reason:      rsFilters[i].Reason,
			MatchRules:  matchRulesToPB(rsFilters[i].MatchRules),
		}
	}
	return pbFilters
}

func matchRulesToPB(rsMatchRules []routing.SettingMatchRule) []*pb.MatchRule {
	pbMatchRules := make([]*pb.MatchRule, len(rsMatchRules))
	for idx := range rsMatchRules {
		pbMatchRules[idx] = &pb.MatchRule{
			Attribute: rsMatchRules[idx].Attribute,
			Value:     rsMatchRules[idx].Value,
			MatchRule: rsMatchRules[idx].MatchRule,
		}
	}
	return pbMatchRules
}

func customFieldsToPB(rsCustomFields []routing.CustomField) []*pb.CustomField {
	pbCustomFields := make([]*pb.CustomField, len(rsCustomFields))
	for i := range rsCustomFields {
		pbCustomFields[i] = &pb.CustomField{
			Name:  rsCustomFields[i].Name,
			Value: rsCustomFields[i].Value,
		}
	}
	return pbCustomFields
}

func pbToTopic(pbToTopics []*pb.Topic) []routing.Topic {
	topics := make([]routing.Topic, len(pbToTopics))
	for idx, topic := range pbToTopics {
		topics[idx] = routing.Topic{
			Type:  topic.Type,
			Value: topic.Value,
		}
	}
	return topics
}
