package utils

import (
	"testing"
	"time"
)

func TestDaysInMonth(t *testing.T) {
	tests := []struct {
		name         string
		month        time.Month
		year         int
		expectedDays int
	}{
		{
			name:         "January 2025 has 31 days",
			month:        time.January,
			year:         2025,
			expectedDays: 31,
		},
		{
			name:         "February 2025, a non-leap year has 28 days",
			month:        time.February,
			year:         2025,
			expectedDays: 28,
		},
		{
			name:         "February 2024, a leap year has 29 days",
			month:        time.February,
			year:         2024,
			expectedDays: 29,
		},
		{
			name:         "April 2025 has 30 days",
			month:        time.April,
			year:         2025,
			expectedDays: 30,
		},
		{
			name:         "December 2025 has 31 days",
			month:        time.December,
			year:         2025,
			expectedDays: 31,
		},
		{
			name:         "January 2026 has 31 days",
			month:        time.January,
			year:         2026,
			expectedDays: 31,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			days := DaysInMonth(tt.month, tt.year)
			if days != tt.expectedDays {
				t.Errorf("DaysInMonth(%v, %d) = %d, expected %d",
					tt.month, tt.year, days, tt.expectedDays)
			}
		})
	}
}
