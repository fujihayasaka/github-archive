package routingsettingsserver

import (
	"strings"

	"github.com/hashicorp/go-multierror"

	"github.com/github/notifyd/internal/pkg/validations"
	pb "github.com/github/notifyd/proto/services/routingsettings"
)

func batchReplaceValidations(request *pb.BatchReplaceRequest) error {
	v := validations.New()
	v.Add(userIDValidator(request.UserId))
	v.Add(validateCustomFieldsForSearching(request.ReplaceByCustomFields))
	v.Add(validateSettings(request.Settings))

	return v.ToError()
}

func userIDValidator(userID int32) func() error {
	return func() error {
		if userID <= 0 {
			return errNoUserID
		}
		return nil
	}
}

func validateSettings(settings []*pb.Setting) func() error {
	return func() error {
		var err error
		for _, setting := range settings {
			if channelErrors := validateChannels(setting.Channels); channelErrors != nil {
				err = multierror.Append(err, channelErrors)
			}
			if topicErrors := validateTopics(setting.Topics); topicErrors != nil {
				err = multierror.Append(err, topicErrors)
			}
			if filterErrors := validateFilters(setting.Filters); filterErrors != nil {
				err = multierror.Append(err, filterErrors)
			}
			if customFieldsForSavingErrors := validateCustomFieldsForSaving(setting.CustomFields); customFieldsForSavingErrors != nil {
				err = multierror.Append(err, customFieldsForSavingErrors)
			}
		}
		return err
	}
}

func validateChannels(channels []*pb.Channel) error {
	var err error
	if len(channels) == 0 {
		err = multierror.Append(err, errInvalidNoChannels)
	}

	// we don't support more than 5 channels now, let's avoid creating duplicates
	if len(channels) > 5 {
		err = multierror.Append(err, errInvalidTooManyChannels)
	}

	channelsNames := make(map[string]bool)
	for _, channel := range channels {
		if strings.TrimSpace(channel.Name) == "" {
			err = multierror.Append(err, errInvalidEmptyChannelName)
		}

		if _, ok := channelsNames[channel.Name]; ok {
			err = multierror.Append(err, errDuplicatedChannels)
		}

		channelsNames[channel.Name] = true
	}

	return err
}

func validateCustomFieldsForSaving(customFields []*pb.CustomField) error {
	// custom field name and value are not empty
	var err error
	for _, field := range customFields {
		if field.Name == "" || field.Value == "" {
			err = multierror.Append(err, errInvalidCustomFieldForSaving)
		}
	}
	return err
}

func validateCustomFieldsForSearching(customFields []*pb.CustomField) func() error {
	return func() error {
		var err error
		// custom field name is not empty
		for _, field := range customFields {
			if field.Name == "" {
				err = multierror.Append(errInvalidCustomFieldForSearching)
			}
		}
		return err
	}
}

func validateTopics(topics []*pb.Topic) error {
	var err error
	// length of topic list must be at least 1
	if len(topics) < 1 {
		err = multierror.Append(errNoTopic)
	}
	// topic type and values are not empty
	for _, field := range topics {
		if field.Type == "" || field.Value == "" {
			err = multierror.Append(errInvalidTopic)
		}
	}
	return err
}

func validateFilters(filters []*pb.Filter) error {
	var err error
	for _, filter := range filters {
		// filter subject type and trigger are not empty
		if filter.SubjectType == "" || filter.Trigger == "" {
			err = multierror.Append(err, errInvalidFilter)
		}
		for _, matchRule := range filter.MatchRules {
			// match rule value and match_rule are not empty
			if matchRule.Value == "" || matchRule.MatchRule == "" {
				err = multierror.Append(err, errInvalidMatchRule)
			}
		}
	}
	return err
}
