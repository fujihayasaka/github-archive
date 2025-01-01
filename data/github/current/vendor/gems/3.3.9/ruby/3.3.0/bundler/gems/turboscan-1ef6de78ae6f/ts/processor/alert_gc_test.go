package processor

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
	"github.com/stretchr/testify/require"
)

func TestAlertGc(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	master := testConfig{ref: "master"}

	// Deliver two alerts
	e.deliverAlerts(master, testAlert("X", "P1"), testAlert("Y", "P2"))

	// 2 alerts, all most recent => nothing to clean
	e.requireAlertSizes(2)
	e.performGC(ts.CleaningTypeAnalysisAssociations)
	e.requireAlertSizes(2)

	// Deliver on same branch one existing alert and one new alert
	e.deliverAlerts(master, testAlert("X", "P3"), testAlert("Z", "P4"))

	// This means we have 2 old (P1, P2), 2 open (P3, P4), 1 fixed (copy of P2) = 5 alerts
	e.requireAlertSizes(5)

	// Running GC should not remove anything, since the fixed alert is on the most_recent analysis
	e.performGC(ts.CleaningTypeAnalysisAssociations)
	e.requireAlertSizes(5)

	// Another delivery with one existing + one new
	e.deliverAlerts(master, testAlert("X", "P5"), testAlert("W", "P6"))

	// This means we have 5 old (P1, P2, P3, P4, copy of P2), 2 open (P5, P6), 2 fixed (copy of P2, copy of P4) = 9 alerts
	e.requireAlertSizes(9)

	// A fixes clean removes the fixed P2 from the old set
	e.performGC(ts.CleaningTypeAnalysisAssociations)
	e.requireAlertSizes(8)
}

func (e *testEnv) requireAlertSizes(expected int) {

	var actual int
	err := e.db.Model(ts.PhysicalAlert{}).Count(&actual).Error
	require.NoError(e.t, err)
	require.Equal(e.t, expected, actual)
	err = e.db.Model(ts.RelatedLocation{}).Count(&actual).Error
	require.NoError(e.t, err)
	require.Equal(e.t, expected, actual)
}
