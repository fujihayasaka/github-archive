// Package models provides the data models for the Licensify service.
package models

import (
	"math"
	"time"
)

// UsageTime represents the time the usage was captured.
type UsageTime struct {
	time.Time
}

// NewUsageTime returns a new UsageTime with the time set to the current time.
func NewUsageTime() *UsageTime {
	return NewUsageTimeFromTime(time.Time{})
}

// NewUsageTimeFromTime returns a new UsageTime with the time set to the given time.
func NewUsageTimeFromTime(t time.Time) *UsageTime {
	return &UsageTime{Time: t}
}

// ConvertYear safely converts an int64 year to int with bounds checking.
func ConvertYear(year int64) int {
	if year < math.MinInt32 || year > math.MaxInt32 {
		return 0
	}
	return int(year)
}

// WithYear returns a new UsageTime with the year set to the given value.
func (t *UsageTime) WithYear(year int64) *UsageTime {
	// Check if the year is within the bounds of int
	convertYear := ConvertYear(year)
	return NewUsageTimeFromTime(time.Date(convertYear, t.Month(), t.Day(), t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), time.UTC))
}

// WithMonthInt returns a new UsageTime with the month set to the given value.
func (t *UsageTime) WithMonthInt(month int64) *UsageTime {
	if month == 0 {
		month = 1
	}
	// Ensure the month is within the valid range [1, 12]
	if month < 1 || month > 12 {
		month = 1
	}
	return NewUsageTimeFromTime(time.Date(t.Year(), time.Month(month), t.Day(), t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), time.UTC))
}

// WithDay returns a new UsageTime with the day set to the given value.
// Note: If the value is 0, it will be set to 1, i.e this will only set dates in the month initialized.
func (t *UsageTime) WithDay(day int) *UsageTime {
	if day == 0 {
		day = 1
	}
	return NewUsageTimeFromTime(time.Date(t.Year(), t.Month(), day, t.Hour(), t.Minute(), t.Second(), t.Nanosecond(), time.UTC))
}

// WithHour returns a new UsageTime with the hour set to the given value.
func (t *UsageTime) WithHour(hour int) *UsageTime {
	return NewUsageTimeFromTime(time.Date(t.Year(), t.Month(), t.Day(), hour, t.Minute(), t.Second(), t.Nanosecond(), time.UTC))
}

// BillableDaysInMonth returns the number of billable days in the month.
func (t *UsageTime) BillableDaysInMonth() int {
	return time.Date(t.Year(), t.Month()+1, 0, 0, 0, 0, 0, time.UTC).Day()
}
