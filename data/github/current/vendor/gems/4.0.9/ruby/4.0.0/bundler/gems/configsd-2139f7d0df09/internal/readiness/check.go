// Package readiness provides a simple readiness check implementation
package readiness

import (
	"context"
	"time"
)

// SimpleReadinessCheck implements httphost.PollingCheck interface
type SimpleReadinessCheck struct {
	checkCount int
}

// NewSimpleReadinessCheck creates a new SimpleReadinessCheck instance
func NewSimpleReadinessCheck() *SimpleReadinessCheck {
	return &SimpleReadinessCheck{}
}

// Success returns true when the service is ready
func (s *SimpleReadinessCheck) Success(ctx context.Context) bool {
	// Increment check count
	s.checkCount++

	// Return false for the first 4 checks to spread delay across 5 polling intervals
	// This creates a total delay of approximately 5 * 100ms = 500ms
	if s.checkCount < 5 {
		return false
	}

	// Simple readiness check - return true after 5 checks for this example
	// In a real application, you might check database connectivity,
	// external service availability, etc.

	return true
}

// CheckInterval returns the time between readiness checks
func (s *SimpleReadinessCheck) CheckInterval() time.Duration {
	return 100 * time.Millisecond
}
