package processor

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

// TestAlertGrouping contains a detailed test of alert grouping for
// multiple refes.
func TestAlertGrouping(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	// We consider deliveries of alerts for two refes B1 and B2
	B1 := testConfig{ref: "B1"}
	B2 := testConfig{ref: "B2"}

	// We compare alerts on the following sets
	B1s := []string{"B1"}
	B2s := []string{"B2"}
	B12s := []string{"B1", "B2"}

	// Deliver alerts X, Y on B1 (baseline)
	e.deliverAlerts(B1, testAlert("X", "P1"), testAlert("Y", "P2"))
	e.performGC(ts.CleaningTypeAnalysisAssociations)

	// GetAlerts B1 = X(P1), Y(P2); GetAlerts B2 = {}; GetAlerts B1+B2 = X(P1), Y(P2)
	e.requireOpen(B1s, testAlert("X", "P1"), testAlert("Y", "P2"))
	e.requireRslv(B1s)
	e.requireOpen(B2s)
	e.requireRslv(B2s)
	e.requireOpen(B12s, testAlert("X", "P1"), testAlert("Y", "P2"))
	e.requireRslv(B12s)

	// Deliver alerts X, Z on B1 (removing Y and adding Z)
	e.deliverAlerts(B1, testAlert("X", "P3"), testAlert("Z", "P4"))
	e.performGC(ts.CleaningTypeAnalysisAssociations)

	// GetAlerts B1 = X(P3), Y(P2)*, Z(P4); GetAlerts B2 = {}; GetAlerts B1+B2 = X(P3), Y(P2)*, Z(P4)
	e.requireOpen(B1s, testAlert("X", "P3"), testAlert("Z", "P4"))
	e.requireRslv(B1s, testAlert("Y", "P2"))
	e.requireOpen(B2s)
	e.requireRslv(B2s)
	e.requireOpen(B12s, testAlert("X", "P3"), testAlert("Z", "P4"))
	e.requireRslv(B12s, testAlert("Y", "P2"))

	// Deliver alerts X, W on B2 (baseline)
	e.deliverAlerts(B2, testAlert("X", "P5"), testAlert("W", "P6"))
	e.performGC(ts.CleaningTypeAnalysisAssociations)

	// GetAlerts B1 = X(P3), Y(P2)*, Z(P4); GetAlerts B2 = X(P5), W(P6); GetAlerts B1+B2 = X(P5), Y(P2)*, Z(P4), W(P6)
	e.requireOpen(B1s, testAlert("X", "P3"), testAlert("Z", "P4"))
	e.requireRslv(B1s, testAlert("Y", "P2"))
	e.requireOpen(B2s, testAlert("X", "P5"), testAlert("W", "P6"))
	e.requireRslv(B2s)
	e.requireOpen(B12s, testAlert("X", "P5"), testAlert("Z", "P4"), testAlert("W", "P6"))
	e.requireRslv(B12s, testAlert("Y", "P2"))

	// Deliver alert W on B1 (removing X, Z and adding W)
	e.deliverAlerts(B1, testAlert("W", "P7"))
	e.performGC(ts.CleaningTypeAnalysisAssociations)

	// GetAlerts B1 = X(P3)*, Y(P2)*, Z(P4)*, W(P7); GetAlerts B2 = X(P5), W(P6); GetAlerts B1+B2 = X(P5), Y(P2)*, Z(P4)*, W(P7)
	e.requireOpen(B1s, testAlert("W", "P7"))
	e.requireRslv(B1s, testAlert("X", "P3"), testAlert("Y", "P2"), testAlert("Z", "P4"))
	e.requireOpen(B2s, testAlert("X", "P5"), testAlert("W", "P6"))
	e.requireRslv(B2s)
	e.requireOpen(B12s, testAlert("X", "P5"), testAlert("W", "P7"))
	e.requireRslv(B12s, testAlert("Y", "P2"), testAlert("Z", "P4"))

	// Deliver alert Y on B2 (removing X, W and adding Y)
	e.deliverAlerts(B2, testAlert("Y", "P8"))
	e.performGC(ts.CleaningTypeAnalysisAssociations)

	// GetAlerts B1 = X(P3)*, Y(P2)*, Z(P4)*, W(P7); GetAlerts B2 = X(P5)*, Y(P8), W(P6)*; GetAlerts B1+B2 = X(P5)*, Y(P8), Z(P4)*, W(P7)
	e.requireOpen(B1s, testAlert("W", "P7"))
	e.requireRslv(B1s, testAlert("X", "P3"), testAlert("Y", "P2"), testAlert("Z", "P4"))
	e.requireOpen(B2s, testAlert("Y", "P8"))
	e.requireRslv(B2s, testAlert("X", "P5"), testAlert("W", "P6"))
	e.requireOpen(B12s, testAlert("Y", "P8"), testAlert("W", "P7"))
	e.requireRslv(B12s, testAlert("X", "P5"), testAlert("Z", "P4"))
}

// TestAlertTransaction contain a test for atomic deliveries of alerts
func TestAlertTransaction(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	// One branch B
	B := testConfig{ref: "B", tool: "CodeQL"}
	Bs := []string{"B"}

	// Deliver alerts X, Y on B (baseline)
	e.deliverAlerts(B, testAlert("X", "P1"), testAlert("Y", "P2"))
	// Cleaning should have no effect
	e.performGC(ts.CleaningTypeAnalysisAssociations)
	e.requireOpen(Bs, testAlert("X", "P1"), testAlert("Y", "P2"))
	e.requireRslv(Bs)

	// A delivery causing one new, one fixed and one unchanged alert.
	a0 := e.deliverAlerts(B, testAlert("X", "P3"), testAlert("Z", "P4"))
	// Cleaning should have no effect
	e.performGC(ts.CleaningTypeAnalysisAssociations)
	e.requireOpen(Bs, testAlert("X", "P3"), testAlert("Z", "P4"))
	e.requireRslv(Bs, testAlert("Y", "P2"))

	// Now do a partial delivery causing one new, one fixed and one unchanged alert.
	B.commitBehavior = CommitBehaviorNone
	a1 := e.deliverAlerts(B, testAlert("X", "P5"), testAlert("W", "P6"))
	// This should not affect the open and resolved (because it is partial)
	e.requireOpen(Bs, testAlert("X", "P3"), testAlert("Z", "P4"))
	e.requireRslv(Bs, testAlert("Y", "P2"))
	// Cleaning here would delete a1 alerts as it is incomplete.

	// Now do another partial delivery causing one new, one fixed and one unchanged alert.
	a2 := e.deliverAlerts(B, testAlert("X", "P7"), testAlert("V", "P8"))
	// Again this should not affect the open and resolved (because it is partial)
	e.requireOpen(Bs, testAlert("X", "P3"), testAlert("Z", "P4"))
	e.requireRslv(Bs, testAlert("Y", "P2"))
	// Cleaning here would delete a1 and a2 alerts as they are incomplete.

	// Now finalize the first analysis, this should affect the open and resolved
	e.finalize(a1, a0)
	e.requireOpen(Bs, testAlert("X", "P5"), testAlert("W", "P6"))
	e.requireRslv(Bs, testAlert("Y", "P2"), testAlert("Z", "P4"))
	// Cleaning here would delete a2 alerts

	// And finalize the second analysis, with respect to a0.
	// Because the baseline changed to a1, then this should error and have no effect
	err := e.analyses.CommitAnalysis(e.ctx, a2)
	require.Error(e.t, err)
	e.requireOpen(Bs, testAlert("X", "P5"), testAlert("W", "P6"))
	e.requireRslv(Bs, testAlert("Y", "P2"), testAlert("Z", "P4"))
	// Cleaning here would delete a2 alerts
	// even though the update failed we should still have a most_recent analysis
	dbtest.RequireCount(t, 1, db.Model(&ts.Analysis{}).Where("most_recent = true"))

	// If we instead finalized with respect to a1, then we get the desired update.
	e.finalize(a2, a1)
	// Cleaning here should delete a0 and a1 alerts
	e.performGC(ts.CleaningTypeAnalysisAssociations)
	e.requireOpen(Bs, testAlert("X", "P7"), testAlert("V", "P8"))
	e.requireRslv(Bs, testAlert("Y", "P2"), testAlert("Z", "P4"))
}
