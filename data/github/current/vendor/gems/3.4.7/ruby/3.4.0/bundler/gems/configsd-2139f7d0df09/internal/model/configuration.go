package model

import (
	"time"
)

// Configuration represents a configuration entry that maps to the twirp Config message.
type Configuration struct {
	Name      string
	Value     string
	Target    *ConfigurationTarget
	Final     bool
	CreatedAt time.Time
	UpdatedAt time.Time
}
