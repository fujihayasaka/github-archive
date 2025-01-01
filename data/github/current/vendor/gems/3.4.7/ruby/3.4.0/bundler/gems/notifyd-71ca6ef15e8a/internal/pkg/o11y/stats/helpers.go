package stats

import (
	"errors"
	time "time"

	clockpkg "github.com/benbjohnson/clock"
	ghstats "github.com/github/go-stats"
)

var (
	errDeliveryTimeIsZero = errors.New("couldn't log delivery.time_to_sent as TriggeredAt time has a zero value")
)

// DurationToSLOBucket finds a bucket tag value for metrics based on time.Duration.
// This is usually used for calculating the elapsed time between two events.
//
// This is used because we cannot create a tag for every unique value of time_to_sent_ms. Instead,
// this buckets the values so we can estimate distributions.
func durationToSLOBucket(elapsedTime time.Duration) string {
	var bucket string

	switch {
	case elapsedTime <= time.Second:
		bucket = "0s-1s"
	case elapsedTime <= 5*time.Second:
		bucket = "1s-5s"
	case elapsedTime <= 30*time.Second:
		bucket = "5s-30s"
	case elapsedTime <= time.Minute:
		bucket = "30s-1m"
	case elapsedTime <= 3*time.Minute:
		bucket = "1m-3m"
	case elapsedTime <= 5*time.Minute:
		bucket = "3m-5m"
	case elapsedTime <= 10*time.Minute:
		bucket = "5m-10m"
	default:
		bucket = "10m-plus"
	}

	return bucket
}

// TrackTimeToSent tracks the time elapsed between the event being triggered and the message being sent.
func TrackTimeToSent(clock clockpkg.Clock, statter ghstats.Client, eventTriggeredAtTime time.Time) error {
	if eventTriggeredAtTime.IsZero() {
		return errDeliveryTimeIsZero
	}
	elapsedTime := clock.Since(eventTriggeredAtTime)

	statter.DistributionMs(
		"delivery.time_to_sent",
		ghstats.Tags{
			"bucket": durationToSLOBucket(elapsedTime),
		},
		elapsedTime,
	)
	return nil
}
