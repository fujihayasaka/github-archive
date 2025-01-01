package processor

import (
	"testing"

	"github.com/github/turboscan/ts"
	"github.com/github/turboscan/ts/dbtest"
)

func TestMatrix_AnalysisKey(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	w1 := testConfig{analysisKey: "W1"}
	w2 := testConfig{analysisKey: "W2"}
	w3 := testConfig{analysisKey: "W3"}

	e.testWorkflows(w1, w2, w3)
}

func TestMatrix_Environment(t *testing.T) {
	db := dbtest.RequireConnection(t)

	e := requireTestEnv(t, db)

	var E1 = map[string]string{
		"os": "linux",
	}
	W1 := testConfig{environment: E1}
	var E2 = map[string]string{
		"os":     "windows",
		"my-var": "my-value",
	}
	W2 := testConfig{environment: E2}
	var E3 = map[string]string{
		"os": "windows",
	}
	W3 := testConfig{environment: E3}

	e.testWorkflows(W1, W2, W3)
}

// testWorkflows runs a series of tests assuming that all three workflows, should
// be considered independent analysis configurations
func (e *testEnv) testWorkflows(w1, w2, w3 testConfig) {
	// Just consider a single branch
	M := "main"
	Ms := []string{M}
	w1.ref = M
	w2.ref = M
	w3.ref = M

	// Deliver two different analyses on the same commit
	w1.commitOid = "XXX"
	w2.commitOid = "XXX"

	e.deliverAlerts(w1, testAlert("X", "P1"), testAlert("Y", "P2"))
	e.deliverAlerts(w2, testAlert("X", "P3"), testAlert("Z", "P4"))
	e.performGC(ts.CleaningTypeAnalysisAssociations)

	// This should mean that the total alerts are the union of these
	e.requireOpen(Ms, testAlert("X", "P3"), testAlert("Y", "P2"), testAlert("Z", "P4"))
	e.requireRslv(Ms)

	// W2 now updates with new alerts
	w2.commitOid = "YYY"
	e.deliverAlerts(w2, testAlert("X", "P5"), testAlert("W", "P6"))
	e.performGC(ts.CleaningTypeAnalysisAssociations)

	// Because W1 is unchanged, Y is still open, but Z is resolved
	e.requireOpen(Ms, testAlert("X", "P5"), testAlert("Y", "P2"), testAlert("W", "P6"))
	e.requireRslv(Ms, testAlert("Z", "P4"))

	// Adding a third workflow W3, can re-open Z
	w3.commitOid = "XXX"
	e.deliverAlerts(w3, testAlert("Z", "P7"))
	e.performGC(ts.CleaningTypeAnalysisAssociations)

	e.requireOpen(Ms, testAlert("X", "P5"), testAlert("Y", "P2"), testAlert("Z", "P7"), testAlert("W", "P6"))
	e.requireRslv(Ms)
}
