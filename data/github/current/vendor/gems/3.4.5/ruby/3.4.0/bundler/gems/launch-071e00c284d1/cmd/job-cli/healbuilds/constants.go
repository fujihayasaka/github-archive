package healbuilds

import (
	"time"

	"github.com/github/launch/constants"
)

const (
	// queuedRunGracePeriod is the amount of time we wait for a queued run before cancelling
	// Actions Service has a daily job that will cancel queued runs older than 24 hours.
	// This time is based on that maximum delay (48 hours) and adds a 2 hour padding.
	queuedRunGracePeriod = time.Hour * 50

	// DefaultPostbackGracePeriod is the amount of time status postbacks have to be processed
	// following azp run completion. After that the healing cronjob will heal the run, and
	// logs and artifacts may not be displayed to the user.
	DefaultPostbackGracePeriod = time.Hour * 3

	DefaultMinHealableJobAge = time.Hour * 24

	// 1 day of padding on top of max postback age to account for healing failures, healing not running due to Freno health checks, etc.
	DefaultMaxHealableJobAge = constants.ActionRunnerStatusSecretDuration + time.Hour*24
)
