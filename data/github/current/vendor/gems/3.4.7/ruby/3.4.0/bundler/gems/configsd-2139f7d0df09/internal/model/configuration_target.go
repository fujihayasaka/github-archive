// Package model defines the core data types and interfaces for the configsd service.
package model

// TargetType represents the type of configuration target.
type TargetType string

// Configuration target types enumeration.
const (
	Repository TargetType = "Repository"
	User       TargetType = "User"
	Business   TargetType = "Business"
	Global     TargetType = "Global"
)

var (
	// GlobalTarget never changes and like Highlander there is only one.
	GlobalTarget = ConfigurationTarget{Type: Global, ID: 0}
)

// String returns the string representation of the TargetType.
func (t TargetType) String() string {
	return string(t)
}

// IsValid returns true if the TargetType is a valid enumeration value.
func (t TargetType) IsValid() bool {
	switch t {
	case Repository,
		User,
		Business,
		Global:
		return true
	}
	return false
}

// ConfigurationTarget represents a target for configuration entries.
type ConfigurationTarget struct {
	Type TargetType
	ID   uint64
}
