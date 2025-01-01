package config

import (
	"time"

	"github.com/github/launch/pkg/launchconfig"
)

type ScheduledConfig struct {
	// how often a worker performs an iteration
	LoopSleepDuration time.Duration
	// how long we wait until we reassign a locked row on the assumption the locking process crashed
	ReassignWorkAfterDuration time.Duration
	// we scatter scheduled events over this duration to mitigate the thundering herd of hourly/midnight events
	ScatterOffsetDuration time.Duration
	// controls how many tasks a worker reserves at a time
	TasksPerTick int
	Environment  launchconfig.AppEnv
	// Expiration time of scheduled build tier information
	TierCacheExpiration time.Duration

	AqueductQueueScheduled string
	AqueductApp            string
}

func (c ScheduledConfig) IsLab() bool {
	return c.Environment == launchconfig.LabAppEnv
}
