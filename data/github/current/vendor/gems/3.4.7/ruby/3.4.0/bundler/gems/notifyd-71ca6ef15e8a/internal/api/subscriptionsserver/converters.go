package subscriptionsserver

import (
	"github.com/github/notifyd/internal/pkg/subscriptions"
	pb "github.com/github/notifyd/proto/services/subscriptions"
)

func pbNewSubscriptionsToMetaSubscriptions(userID int64, pbCreateRequest []*pb.BatchReplaceCreateRequest) []*subscriptions.MetaSubscription {
	subscriptionsToCreate := make([]*subscriptions.MetaSubscription, len(pbCreateRequest))
	for idx, toCreate := range pbCreateRequest {
		subscriptionsToCreate[idx] = &subscriptions.MetaSubscription{
			UserID: userID,
			Details: subscriptions.Details{
				Reason:       toCreate.Reason,
				Filters:      pbToFilters(toCreate.Filters),
				Topics:       pbToTopic(toCreate.Topics),
				CustomFields: pbToCustomFields(toCreate.CustomFields),
			},
		}
	}
	return subscriptionsToCreate
}

func pbToTopic(pbToTopics []*pb.Topic) []subscriptions.Topic {
	topics := make([]subscriptions.Topic, len(pbToTopics))
	for idx, topic := range pbToTopics {
		topics[idx] = subscriptions.Topic{
			Type:  topic.Type,
			Value: topic.Value,
		}
	}
	return topics
}

func pbToCustomFields(pbToCustomFields []*pb.CustomField) []subscriptions.CustomField {
	fields := make([]subscriptions.CustomField, len(pbToCustomFields))
	for i, field := range pbToCustomFields {
		fields[i] = subscriptions.CustomField{
			Name:  field.Name,
			Value: field.Value,
		}
	}
	return fields
}

func pbToFilters(pbFilters []*pb.Filter) []subscriptions.Filter {
	filters := make([]subscriptions.Filter, len(pbFilters))
	for idx, filter := range pbFilters {
		var matchRules = make([]subscriptions.MatchRule, len(filter.MatchRules))
		for idx, matchRule := range filter.MatchRules {
			matchRules[idx] = subscriptions.MatchRule{
				Attribute: matchRule.Attribute,
				Value:     matchRule.Value,
				MatchRule: matchRule.MatchRule,
			}
		}
		filters[idx] = subscriptions.Filter{
			SubjectType: filter.SubjectType,
			Trigger:     filter.Trigger,
			MatchRules:  matchRules,
		}
	}

	return filters
}
