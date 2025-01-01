package v210turboscan

import (
	"github.com/github/turboscan/ts/transforms"
	"golang.org/x/exp/slices"
)

// Tag is an intermediary type to ensure that the `NotificationsWithtags` method cannot be used with just strings.
type Tag string

const (
	BaselineExtracted     Tag = "expected-extracted-files"
	SuccessfullyExtracted Tag = "successfully-extracted-files"
)

// NotificationsWithTag returns a filtered list of s.Notification that are tagged in the sarif by the tag provided.
func (s *ToolComponent) NotificationsWithTag(tag Tag) []*ReportingDescriptor {
	return transforms.Filter(s.Notifications, func(n *ReportingDescriptor) bool {
		return n.Properties != nil && slices.Contains(n.Properties.Tags, string(tag))
	})
}

// ToolComponentIndicator represents an index identifying a particular ToolComponent.
// It either represents
// a) the driver or
// b) an unspecified tool component, e.g. if the result did not reference one, or
// c) the index into the extensions list if the tool component is one of the extensions
type ToolComponentIndicator int

const ToolComponentDriver = -1
const ToolComponentUnknown = -2

func (i ToolComponentIndicator) IsDriver() bool {
	return i == ToolComponentDriver
}

func (i ToolComponentIndicator) IsUnknown() bool {
	return i == ToolComponentUnknown
}

func (i ToolComponentIndicator) IsExtension() bool {
	return i >= 0
}
