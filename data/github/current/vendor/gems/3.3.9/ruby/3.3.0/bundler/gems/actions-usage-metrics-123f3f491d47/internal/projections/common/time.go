package common

import (
	"time"
)

type ProjectionAggregationInterval string

const (
	ProjectionAggregationIntervalDaily   ProjectionAggregationInterval = "daily"
	ProjectionAggregationIntervalMonthly ProjectionAggregationInterval = "monthly"
	ProjectionAggregationIntervalNone    ProjectionAggregationInterval = "none"
)

func (p ProjectionAggregationInterval) String() string {
	return string(p)
}

func GetWeekStartDate(dateTime time.Time) time.Time {
	weekday := int(dateTime.Weekday())
	if weekday == int(time.Sunday) {
		weekday = 7 // We want Mon-Sun, not Sun-Sat
	}
	subtractDays := weekday - int(time.Monday)
	dateTime = dateTime.AddDate(0, 0, -subtractDays).Truncate(24 * time.Hour) // get the start of Monday, not sometime in the middle of Monday
	return dateTime
}
