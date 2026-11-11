// Package coretest provides test helpers for the memory core package.
package coretest

import (
	"testing"
	"time"

	"github.com/github/sweagentd/internal/memory/core"
)

// FreezeNow pins the wall-clock used by Memory operations such as AddVote to
// the given instant for the duration of the test. The original clock is
// restored via t.Cleanup.
//
// Tests that exercise clock-based invariants in AddVote must use this helper,
// otherwise their fixture timestamps drift relative to real time and the tests
// become flaky / time-dependent.
func FreezeNow(t testing.TB, now time.Time) {
	t.Helper()
	restore := core.SetNowFunc(now.UTC)
	t.Cleanup(restore)
}
