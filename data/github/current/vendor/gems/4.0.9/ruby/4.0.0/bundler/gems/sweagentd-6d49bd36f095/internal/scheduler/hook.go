// Package scheduler implements the interval trigger scheduler service.
package scheduler

import (
	"context"
	"time"

	schedulerstore "github.com/github/sweagentd/internal/scheduler/store"
)

// SchedulingHook allows external systems to influence scheduler behavior.
type SchedulingHook interface {
	// GetBatchSize returns the number of triggers to process per tick.
	GetBatchSize(ctx context.Context) int

	// ShouldProcess returns whether a specific trigger should be processed now.
	ShouldProcess(ctx context.Context, triggerID string, scopeID int64) bool

	// GetScatterDuration returns the scatter window applied on top of the
	// schedule's anchor instant.
	GetScatterDuration(schedule schedulerstore.Schedule) time.Duration
}

// DefaultSchedulingHook provides reasonable defaults for scheduling.
type DefaultSchedulingHook struct {
	maxBatchSize int
}

// NewDefaultSchedulingHook creates a DefaultSchedulingHook with the given max batch size.
func NewDefaultSchedulingHook(maxBatchSize int) *DefaultSchedulingHook {
	return &DefaultSchedulingHook{maxBatchSize: maxBatchSize}
}

// GetBatchSize returns the configured max batch size.
func (h *DefaultSchedulingHook) GetBatchSize(_ context.Context) int {
	return h.maxBatchSize
}

// ShouldProcess always returns true for the default hook.
func (h *DefaultSchedulingHook) ShouldProcess(_ context.Context, _ string, _ int64) bool {
	return true
}

// GetScatterDuration returns the scatter window for the given schedule shape.
func (h *DefaultSchedulingHook) GetScatterDuration(schedule schedulerstore.Schedule) time.Duration {
	switch schedule.IntervalType {
	case schedulerstore.IntervalTypeHourly:
		return schedulerstore.HourlyScatterDuration
	case schedulerstore.IntervalTypeWeekly:
		switch {
		case schedule.IsAnchoredHour() && schedule.IsAnchoredDay():
			return schedulerstore.AnchoredWeeklyScatterDuration
		case schedule.IsAnchoredDay():
			return schedulerstore.WeeklyDayAnytimeScatterDuration
		default:
			return schedulerstore.WeeklyScatterDuration
		}
	default:
		if schedule.IsAnchoredHour() {
			return schedulerstore.AnchoredDailyScatterDuration
		}
		return schedulerstore.DailyScatterDuration
	}
}
