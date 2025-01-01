package matchengine

import "github.com/github/notifyd/internal/pkg/notify"

// StringSet is a map of string to boolean.
type StringSet map[string]bool

// attributesToStringSet transforms attributes on notification message from array to the map for faster matching
//
//	[{name: "has_label", value: "1"}]
//
//	will be transformed to
//
//	  "has_label" => {
//	    "1" => true
//	  }
func attributesToStringSet(notificationAttributes []notify.Attribute) map[string]StringSet {
	attributes := map[string]StringSet{}
	for _, attribute := range notificationAttributes {
		if _, ok := attributes[attribute.Name]; !ok {
			attributes[attribute.Name] = StringSet{}
		}

		attributes[attribute.Name][attribute.Value] = true
	}
	return attributes
}
