package models

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestEndOfMonth(t *testing.T) {
	// Get the current time
	currentTime := time.Now().UTC()
	currentYear, currentMonth, _ := currentTime.Date()
	location := currentTime.Location()

	// Calculate the expected end of the month
	firstOfNextMonth := time.Date(currentYear, currentMonth+1, 1, 0, 0, 0, 0, location)
	expectedEndOfMonth := firstOfNextMonth.Add(-time.Second).Unix()
	assert.Equal(t, expectedEndOfMonth, EndOfMonth())
}

func TestRemainingSecondsThisMonth(t *testing.T) {
	// Mock the now time var
	currentTime := time.Now().UTC()
	Now = func() time.Time {
		return currentTime
	}

	// Find the start of the next month.
	year, month, _ := currentTime.Date()
	nextMonth := time.Date(year, month+1, 1, 0, 0, 0, 0, currentTime.Location())
	expectedRemainingSeconds := int64(nextMonth.Sub(currentTime).Seconds())

	assert.Equal(t, expectedRemainingSeconds, *RemainingSecondsThisMonth())
}
