package scheduler

import (
	"math"
	"testing"
	"time"

	schedulerstore "github.com/github/sweagentd/internal/scheduler/store"
	"github.com/stretchr/testify/assert"
)

// intPtr is a tiny helper used in these table-driven tests to point at an int
// literal without a one-off variable declaration per case.
func intPtr(i int) *int { return &i }

// utc constructs a time.Time at UTC from the given components for readability.
func utc(year int, month time.Month, day, hour, minute int) time.Time {
	return time.Date(year, month, day, hour, minute, 0, 0, time.UTC)
}

// hook is the default scheduling hook used in the math tests. Anchor-aware
// jitter windows are sourced from the constants in schedulerstore.
var hook = NewDefaultSchedulingHook(10)

func TestComputeNextRunAt_Hourly(t *testing.T) {
	schedule := schedulerstore.Schedule{IntervalType: schedulerstore.IntervalTypeHourly}

	tests := []struct {
		name          string
		now           time.Time
		scatterOffset float64
		allowCurrent  bool
		expectedRunAt time.Time
	}{
		{
			name:          "scatter 0: exact top of next hour",
			now:           utc(2026, time.March, 1, 12, 30),
			scatterOffset: 0.0,
			allowCurrent:  false,
			expectedRunAt: utc(2026, time.March, 1, 13, 0),
		},
		{
			name:          "scatter 0.5: top of next hour + 5min",
			now:           utc(2026, time.March, 1, 12, 30),
			scatterOffset: 0.5,
			allowCurrent:  false,
			expectedRunAt: utc(2026, time.March, 1, 13, 5),
		},
		{
			name:          "scatter 0.999: just under +10min",
			now:           utc(2026, time.March, 1, 12, 30),
			scatterOffset: 0.999,
			allowCurrent:  false,
			expectedRunAt: utc(2026, time.March, 1, 13, 0).Add(time.Duration(0.999 * float64(10*time.Minute))),
		},
		{
			name:          "initial: scatter 0.5 at 11:01 -> current window (11:05) still in future",
			now:           utc(2026, time.March, 1, 11, 1),
			scatterOffset: 0.5,
			allowCurrent:  true,
			expectedRunAt: utc(2026, time.March, 1, 11, 5),
		},
		{
			name:          "initial: scatter 0.5 at 12:06 -> current window already passed, schedule 13:05",
			now:           utc(2026, time.March, 1, 12, 6),
			scatterOffset: 0.5,
			allowCurrent:  true,
			expectedRunAt: utc(2026, time.March, 1, 13, 5),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := computeNextRunAt(tt.now, schedule, tt.scatterOffset, hook, tt.allowCurrent)
			assert.True(t, got.Equal(tt.expectedRunAt), "got %s, want %s", got, tt.expectedRunAt)
		})
	}
}

func TestComputeNextRunAt_DailyAnytime_PreservesLegacyBehaviour(t *testing.T) {
	// Anchors absent -> midnight + 4h jitter, matching today's behaviour.
	schedule := schedulerstore.Schedule{IntervalType: schedulerstore.IntervalTypeDaily}

	tests := []struct {
		name          string
		now           time.Time
		scatterOffset float64
		allowCurrent  bool
		expectedRunAt time.Time
	}{
		{
			name:          "scatter 0 at noon -> next midnight",
			now:           utc(2026, time.March, 1, 12, 0),
			scatterOffset: 0.0,
			allowCurrent:  false,
			expectedRunAt: utc(2026, time.March, 2, 0, 0),
		},
		{
			name:          "scatter 0.5 at noon -> next midnight + 2h",
			now:           utc(2026, time.March, 1, 12, 0),
			scatterOffset: 0.5,
			allowCurrent:  false,
			expectedRunAt: utc(2026, time.March, 2, 2, 0),
		},
		{
			name:          "initial: scatter 0.5 at 01:00 -> today midnight + 2h (still in future)",
			now:           utc(2026, time.March, 1, 1, 0),
			scatterOffset: 0.5,
			allowCurrent:  true,
			expectedRunAt: utc(2026, time.March, 1, 2, 0),
		},
		{
			name:          "initial: scatter 0.5 at 05:00 -> current window passed, next midnight + 2h",
			now:           utc(2026, time.March, 1, 5, 0),
			scatterOffset: 0.5,
			allowCurrent:  true,
			expectedRunAt: utc(2026, time.March, 2, 2, 0),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := computeNextRunAt(tt.now, schedule, tt.scatterOffset, hook, tt.allowCurrent)
			assert.True(t, got.Equal(tt.expectedRunAt), "got %s, want %s", got, tt.expectedRunAt)
		})
	}
}

func TestComputeNextRunAt_DailyAnchored(t *testing.T) {
	// Daily @ 8am UTC: jitter window is 15 min, so anchor=08:00, candidate=08:00..08:15.
	schedule := schedulerstore.Schedule{
		IntervalType:  schedulerstore.IntervalTypeDaily,
		AnchorHourUTC: intPtr(8),
	}

	tests := []struct {
		name          string
		now           time.Time
		scatterOffset float64
		allowCurrent  bool
		expectedRunAt time.Time
	}{
		{
			name:          "post-execute: scatter 0 at 08:05 -> tomorrow 08:00 exact",
			now:           utc(2026, time.March, 1, 8, 5),
			scatterOffset: 0.0,
			allowCurrent:  false,
			expectedRunAt: utc(2026, time.March, 2, 8, 0),
		},
		{
			name:          "post-execute: scatter 1 at 08:05 -> tomorrow ~08:15 (clamp keeps it inside the 15m window)",
			now:           utc(2026, time.March, 1, 8, 5),
			scatterOffset: 1.0,
			allowCurrent:  false,
			// Clamp lifts 1.0 down to math.Nextafter(1.0, 0); the run lands one tick
			// before the next-day 08:15 boundary, which is the intended upper bound.
			expectedRunAt: utc(2026, time.March, 2, 8, 0).Add(time.Duration(float64(15*time.Minute) * math.Nextafter(1.0, 0))),
		},
		{
			name:          "initial: scatter 0.5 at 07:00 -> today 08:07:30 (current window in future)",
			now:           utc(2026, time.March, 1, 7, 0),
			scatterOffset: 0.5,
			allowCurrent:  true,
			expectedRunAt: utc(2026, time.March, 1, 8, 0).Add(time.Duration(0.5 * float64(15*time.Minute))),
		},
		{
			name:          "initial: scatter 0.5 at 09:00 -> tomorrow 08:07:30 (current window already fired)",
			now:           utc(2026, time.March, 1, 9, 0),
			scatterOffset: 0.5,
			allowCurrent:  true,
			expectedRunAt: utc(2026, time.March, 2, 8, 0).Add(time.Duration(0.5 * float64(15*time.Minute))),
		},
		{
			name:          "cross-month: scatter 0 at 08:01 on Jan 31 -> Feb 1 08:00",
			now:           utc(2026, time.January, 31, 8, 1),
			scatterOffset: 0.0,
			allowCurrent:  false,
			expectedRunAt: utc(2026, time.February, 1, 8, 0),
		},
		{
			name:          "leap day: scatter 0 at 08:01 on Feb 28 2024 -> Feb 29 2024",
			now:           utc(2024, time.February, 28, 8, 1),
			scatterOffset: 0.0,
			allowCurrent:  false,
			expectedRunAt: utc(2024, time.February, 29, 8, 0),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := computeNextRunAt(tt.now, schedule, tt.scatterOffset, hook, tt.allowCurrent)
			assert.True(t, got.Equal(tt.expectedRunAt), "got %s, want %s", got, tt.expectedRunAt)
		})
	}
}

func TestComputeNextRunAt_WeeklyAnytime_PreservesLegacyBehaviour(t *testing.T) {
	// No anchors -> Monday 00:00 UTC + 12h scatter, matching today's behaviour.
	schedule := schedulerstore.Schedule{IntervalType: schedulerstore.IntervalTypeWeekly}

	// 2026-03-02 is a Monday.
	monday := utc(2026, time.March, 2, 0, 0)
	wednesday := utc(2026, time.March, 4, 12, 0)
	sunday := utc(2026, time.March, 1, 12, 0)

	tests := []struct {
		name          string
		now           time.Time
		scatterOffset float64
		allowCurrent  bool
		expectedRunAt time.Time
	}{
		{
			name:          "post-execute Wed -> next Mon 00:00",
			now:           wednesday,
			scatterOffset: 0.0,
			allowCurrent:  false,
			expectedRunAt: monday.AddDate(0, 0, 7),
		},
		{
			name:          "post-execute Mon -> next Mon 00:00 (advance a full week)",
			now:           monday,
			scatterOffset: 0.0,
			allowCurrent:  false,
			expectedRunAt: monday.AddDate(0, 0, 7),
		},
		{
			name:          "initial Sun -> tomorrow Mon (current window in future)",
			now:           sunday,
			scatterOffset: 0.5,
			allowCurrent:  true,
			expectedRunAt: monday.Add(6 * time.Hour),
		},
		{
			name:          "initial Wed -> current week's Mon already passed, next Mon + scatter",
			now:           wednesday,
			scatterOffset: 0.5,
			allowCurrent:  true,
			expectedRunAt: monday.AddDate(0, 0, 7).Add(6 * time.Hour),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := computeNextRunAt(tt.now, schedule, tt.scatterOffset, hook, tt.allowCurrent)
			assert.True(t, got.Equal(tt.expectedRunAt), "got %s, want %s", got, tt.expectedRunAt)
		})
	}
}

func TestComputeNextRunAt_WeeklyDayAnytime(t *testing.T) {
	// "Weekly Tuesdays anytime": anchor Tue 00:00 UTC, jitter window 24h.
	schedule := schedulerstore.Schedule{
		IntervalType:    schedulerstore.IntervalTypeWeekly,
		AnchorDayOfWeek: intPtr(int(time.Tuesday)),
	}

	monday := utc(2026, time.March, 2, 12, 0)
	tuesday := utc(2026, time.March, 3, 0, 0)
	wednesday := utc(2026, time.March, 4, 12, 0)

	tests := []struct {
		name          string
		now           time.Time
		scatterOffset float64
		allowCurrent  bool
		expectedRunAt time.Time
	}{
		{
			name:          "post-execute Mon -> next Tuesday 00:00 + scatter",
			now:           monday,
			scatterOffset: 0.0,
			allowCurrent:  false,
			expectedRunAt: tuesday,
		},
		{
			name:          "post-execute Wed -> next Tue (one week later) + scatter",
			now:           wednesday,
			scatterOffset: 0.5,
			allowCurrent:  false,
			expectedRunAt: tuesday.AddDate(0, 0, 7).Add(12 * time.Hour),
		},
		{
			name:          "initial Mon -> coming Tuesday at scatter offset",
			now:           monday,
			scatterOffset: 0.5,
			allowCurrent:  true,
			expectedRunAt: tuesday.Add(12 * time.Hour),
		},
		{
			name:          "scatter 0.999 stays within the chosen UTC day",
			now:           monday,
			scatterOffset: 0.999,
			allowCurrent:  false,
			expectedRunAt: tuesday.Add(time.Duration(0.999 * float64(24*time.Hour))),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := computeNextRunAt(tt.now, schedule, tt.scatterOffset, hook, tt.allowCurrent)
			assert.True(t, got.Equal(tt.expectedRunAt), "got %s, want %s", got, tt.expectedRunAt)
			assert.Equal(t, time.Tuesday, got.Weekday(), "weekly-day-anytime must fire on the chosen weekday")
		})
	}
}

func TestComputeNextRunAt_WeeklyDayAndHour(t *testing.T) {
	// "Weekly Sundays @ 23:00 UTC": jitter window 30 min.
	schedule := schedulerstore.Schedule{
		IntervalType:    schedulerstore.IntervalTypeWeekly,
		AnchorDayOfWeek: intPtr(int(time.Sunday)),
		AnchorHourUTC:   intPtr(23),
	}

	tests := []struct {
		name          string
		now           time.Time
		scatterOffset float64
		allowCurrent  bool
		expectedRunAt time.Time
	}{
		{
			name:          "initial: Sun 22:00 -> same Sun 23:00 + scatter (current window in future)",
			now:           utc(2026, time.March, 1, 22, 0), // Sunday
			scatterOffset: 0.5,
			allowCurrent:  true,
			expectedRunAt: utc(2026, time.March, 1, 23, 0).Add(15 * time.Minute),
		},
		{
			name:          "initial: Sun 23:30 -> next Sun 23:00 + scatter (window just fired)",
			now:           utc(2026, time.March, 1, 23, 30), // Sunday
			scatterOffset: 0.5,
			allowCurrent:  true,
			expectedRunAt: utc(2026, time.March, 8, 23, 0).Add(15 * time.Minute),
		},
		{
			name:          "post-execute Mon -> next Sun 23:00 (6 days away)",
			now:           utc(2026, time.March, 2, 0, 0), // Monday 00:00
			scatterOffset: 0.0,
			allowCurrent:  false,
			expectedRunAt: utc(2026, time.March, 8, 23, 0),
		},
		{
			name:          "year boundary: post-execute Dec 28 2025 (Sun) -> Jan 4 2026 (next Sun)",
			now:           utc(2025, time.December, 28, 23, 5),
			scatterOffset: 0.0,
			allowCurrent:  false,
			expectedRunAt: utc(2026, time.January, 4, 23, 0),
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := computeNextRunAt(tt.now, schedule, tt.scatterOffset, hook, tt.allowCurrent)
			assert.True(t, got.Equal(tt.expectedRunAt), "got %s, want %s", got, tt.expectedRunAt)
		})
	}
}

func TestComputeNextRunAt_StableJitter(t *testing.T) {
	// Same record + same scatter -> same minute past anchor across many recomputes.
	schedule := schedulerstore.Schedule{
		IntervalType:  schedulerstore.IntervalTypeDaily,
		AnchorHourUTC: intPtr(8),
	}
	scatterOffset := 0.4213

	now := utc(2026, time.March, 1, 9, 0)
	first := computeNextRunAt(now, schedule, scatterOffset, hook, false)

	// After the trigger "fires", recompute from a slightly later now. Same offset within window.
	nextNow := first.Add(time.Second)
	second := computeNextRunAt(nextNow, schedule, scatterOffset, hook, false)

	// Both should be 08:00 + (0.4213 * 15min) = 08:06:19.5 on consecutive days.
	expectedOffset := time.Duration(scatterOffset * float64(15*time.Minute))
	assert.True(t, first.Equal(utc(2026, time.March, 2, 8, 0).Add(expectedOffset)))
	assert.True(t, second.Equal(utc(2026, time.March, 3, 8, 0).Add(expectedOffset)))

	// And the *minute past anchor* is identical.
	assert.Equal(t, first.Sub(utc(2026, time.March, 2, 8, 0)), second.Sub(utc(2026, time.March, 3, 8, 0)))
}

func TestCalculateInitialNextRunAt_LegacySignature_NoAnchors(t *testing.T) {
	// Sanity-check the public signature agentsync still calls. Returns a future timestamp;
	// exact value depends on wall clock, so this is a soft check.
	got := CalculateInitialNextRunAt(schedulerstore.IntervalTypeDaily, 0.5, hook)
	assert.True(t, got.After(time.Now().UTC()), "next run should be in the future")
}

func TestGenerateScatterOffset_RangeIsHalfOpen(t *testing.T) {
	for range 1000 {
		v := GenerateScatterOffset()
		assert.GreaterOrEqual(t, v, 0.0)
		assert.Less(t, v, 1.0)
	}
}

func TestClampScatterOffset(t *testing.T) {
	tests := []struct {
		name string
		in   float64
		want float64
	}{
		{"zero", 0, 0},
		{"mid", 0.5, 0.5},
		{"just under one", math.Nextafter(1.0, 0), math.Nextafter(1.0, 0)},
		{"exactly one", 1.0, math.Nextafter(1.0, 0)},
		{"greater than one", 1.5, math.Nextafter(1.0, 0)},
		{"negative", -0.1, 0},
		{"NaN", math.NaN(), 0},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.InDelta(t, tt.want, clampScatterOffset(tt.in), 0)
		})
	}
}

func TestComputeNextRunAt_ClampsOutOfRangeScatterOffset(t *testing.T) {
	// Without the read-side clamp, scatterOffset=1.0 × 24h window lands exactly
	// on the next-day anchor — i.e. the schedule appears to skip a cycle.
	schedule := schedulerstore.Schedule{
		IntervalType:    schedulerstore.IntervalTypeWeekly,
		AnchorDayOfWeek: intPtr(2), // Tuesday, no hour -> WeeklyDayAnytime (24h)
	}
	now := utc(2026, time.March, 3, 6, 0) // Tuesday 06:00 UTC

	got := computeNextRunAt(now, schedule, 1.0, hook, true)
	// Clamp lifts 1.0 down to just under 1.0, so the candidate stays inside
	// the chosen Tuesday rather than spilling into Wednesday.
	assert.Equal(t, time.Tuesday, got.Weekday(), "clamped offset must keep the run inside the anchored day")
}

func TestCurrentWindowAnchor_RejectsOutOfRangeAnchorValues(t *testing.T) {
	// time.Date normalises hour=25 into the next day; without a guard a corrupt
	// AnchorHourUTC silently shifts every weekly run by 24h. Same idea for day.
	now := utc(2026, time.March, 4, 12, 0) // Wednesday 12:00 UTC

	bad := schedulerstore.Schedule{
		IntervalType:    schedulerstore.IntervalTypeWeekly,
		AnchorDayOfWeek: intPtr(9),  // invalid
		AnchorHourUTC:   intPtr(25), // invalid
	}
	good := schedulerstore.Schedule{IntervalType: schedulerstore.IntervalTypeWeekly}

	assert.Equal(t, currentWindowAnchor(now, good), currentWindowAnchor(now, bad),
		"out-of-range anchor fields must fall back to legacy weekly defaults")
}
