// Package featureswitches implements a way to check if a feature switches are enabled.
package featureswitches

var (
	defaults = map[string]bool{
		"notify_subscribers": true,
		"notify_actor":       false,
	}
)

// IsEnabled checks the given flag from the map, applying defaults if needed
func IsEnabled(featureSwitches map[string]bool, name string) bool {
	if enabled, found := featureSwitches[name]; found {
		return enabled
	}
	if enabled, found := defaults[name]; found {
		return enabled
	}
	return false
}
