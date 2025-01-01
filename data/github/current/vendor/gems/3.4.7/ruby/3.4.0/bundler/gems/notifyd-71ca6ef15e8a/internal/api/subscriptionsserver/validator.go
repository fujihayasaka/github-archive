package subscriptionsserver

import (
	"github.com/github/notifyd/internal/pkg/errors"
	pb "github.com/github/notifyd/proto/services/subscriptions"
)

var (
	errNoUserID                       = errors.New("user id must be specified")
	errNoReason                       = errors.New("reason is not valid")
	errNoTopic                        = errors.New("at least one topic must be specified")
	errInvalidTopic                   = errors.New("type and value must be specified for each topic")
	errInvalidFilter                  = errors.New("subject type and trigger must be specified for each filter")
	errInvalidMatchRule               = errors.New("attribute, value and match_rule must be specified for each match rule")
	errInvalidCustomFieldForSearching = errors.New("name must be specified for each custom field search")
	errInvalidCustomFieldForSaving    = errors.New("name and value be specified for each saved custom field")
)

func getValidation(request *pb.GetRequest) error {
	if request.UserId < 0 {
		return errNoUserID
	}

	return validateCustomFieldsForSearching(request.FilterByCustomFields)
}

func batchReplaceValidations(request *pb.BatchReplaceRequest) error {
	if request.UserId <= 0 {
		return errNoUserID
	}

	if err := validateCustomFieldsForSearching(request.ReplaceByCustomFields); err != nil {
		return err
	}

	for _, toCreate := range request.NewSubscriptions {
		if toCreate.Reason == "" {
			return errNoReason
		}
		if err := validateTopics(toCreate.Topics); err != nil {
			return err
		}
		if err := validateFilters(toCreate.Filters); err != nil {
			return err
		}
		if err := validateCustomFieldsForSaving(toCreate.CustomFields); err != nil {
			return err
		}
	}

	return nil
}

func validateCustomFieldsForSaving(customFields []*pb.CustomField) error {
	// custom field name and value are not empty
	for _, field := range customFields {
		if field.Name == "" || field.Value == "" {
			return errInvalidCustomFieldForSaving
		}
	}
	return nil
}

func validateCustomFieldsForSearching(customFields []*pb.CustomField) error {
	// custom field name is not empty
	for _, field := range customFields {
		if field.Name == "" {
			return errInvalidCustomFieldForSearching
		}
	}
	return nil
}

func validateTopics(topics []*pb.Topic) error {
	// length of topic list must be at least 1
	if len(topics) < 1 {
		return errNoTopic
	}
	// topic type and values are not empty
	for _, field := range topics {
		if field.Type == "" || field.Value == "" {
			return errInvalidTopic
		}
	}
	return nil
}

func validateFilters(filters []*pb.Filter) error {
	for _, filter := range filters {
		// filter subject type and trigger are not empty
		if filter.SubjectType == "" || filter.Trigger == "" {
			return errInvalidFilter
		}
		for _, matchRule := range filter.MatchRules {
			// match rule value and match_rule are not empty
			if matchRule.Value == "" || matchRule.MatchRule == "" {
				return errInvalidMatchRule
			}
		}
	}
	return nil
}
