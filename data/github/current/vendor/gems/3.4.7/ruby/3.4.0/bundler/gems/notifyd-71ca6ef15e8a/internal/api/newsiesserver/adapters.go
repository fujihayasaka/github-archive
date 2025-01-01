package newsiesserver

import (
	"github.com/github/notifyd/internal/api/newsiesservice"
	"github.com/github/notifyd/internal/pkg/errors"
	"github.com/github/notifyd/internal/pkg/routing"
	"github.com/github/notifyd/internal/pkg/subscriptions"
	pb "github.com/github/notifyd/proto/services/newsies"
)

// ErrUnknownThreadType is used whenever the conversion between protobuf thread types and domain
// thread types finds an unknown value.
var ErrUnknownThreadType = errors.New("unknown thread type")

// threadTypesAdapter transforms the ThreadTypes received from the protobuf request into the structs
// that the domain services expect.
func threadTypesAdapter(types []pb.ThreadTypes) ([]newsiesservice.ThreadType, error) {
	newTypes := make([]newsiesservice.ThreadType, 0, len(types))

	for _, t := range types {
		switch t {
		case pb.ThreadTypes_ISSUE:
			newTypes = append(newTypes, newsiesservice.Issue)
		case pb.ThreadTypes_PULL_REQUEST:
			newTypes = append(newTypes, newsiesservice.PullRequest)
		case pb.ThreadTypes_DISCUSSION:
			newTypes = append(newTypes, newsiesservice.Discussion)
		case pb.ThreadTypes_SECURITY_ALERT:
			newTypes = append(newTypes, newsiesservice.SecurityAlert)
		case pb.ThreadTypes_RELEASE:
			newTypes = append(newTypes, newsiesservice.Release)
		default:
			return []newsiesservice.ThreadType{}, errors.Wrapf(ErrUnknownThreadType, "type %s", t)
		}
	}

	return newTypes, nil
}

func subscriptionsCustomFieldsAdapter(fields []*pb.CustomField) []subscriptions.CustomField {
	result := make([]subscriptions.CustomField, len(fields))
	for i, field := range fields {
		result[i] = subscriptions.CustomField{
			Name:  field.Name,
			Value: field.Value,
		}
	}
	return result
}

func settingsCustomFieldsAdapter(pbCustomFields []*pb.CustomField) []routing.CustomField {
	var result []routing.CustomField
	for _, field := range pbCustomFields {
		result = append(result, routing.CustomField{
			Name:  field.Name,
			Value: field.Value,
		})
	}
	return result
}
