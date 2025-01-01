package alerts

import (
	"github.com/github/turboscan/ts"
)

// AlertDiff represents the difference between two sets of alerts
type AlertDiff struct {
	RemovedIDs ts.AlertIDSet
	Removed    []*ts.PhysicalAlert
	AddedIDs   ts.AlertIDSet
	Added      []*ts.PhysicalAlert
}

// OpenDiff represents the difference between two sets of alerts, when the baseline is only open alerts
type OpenDiff AlertDiff

// FixedDiff represents the difference between two sets of alerts, when the baseline is only fixed alerts
type FixedDiff AlertDiff

// compareAlerts diffs the two alert sets.
func compareAlerts(before []*ts.PhysicalAlert, after []*ts.PhysicalAlert) AlertDiff {
	beforeIDs := logicalIDs(before)
	afterIDs := logicalIDs(after)

	removedIDs := ts.AlertIDSet{}
	removed := []*ts.PhysicalAlert{}
	for _, a := range before {
		if !afterIDs[a.LogicalAlertID] {
			removedIDs[a.LogicalAlertID] = true
			removed = append(removed, a)
		}
	}
	addedIDs := ts.AlertIDSet{}
	added := []*ts.PhysicalAlert{}
	for _, a := range after {
		if !beforeIDs[a.LogicalAlertID] {
			addedIDs[a.LogicalAlertID] = true
			added = append(added, a)
		}
	}
	return AlertDiff{
		RemovedIDs: removedIDs,
		Removed:    removed,
		AddedIDs:   addedIDs,
		Added:      added,
	}
}

// Create a set of all logical alert ids in the given slice.
func logicalIDs(alerts []*ts.PhysicalAlert) ts.AlertIDSet {
	ids := make(ts.AlertIDSet, len(alerts))
	for _, a := range alerts {
		ids[a.LogicalAlertID] = true
	}
	return ids
}

// CompareAlerts will compare the two set of alerts
// but it will return two diffs: One for the open set and another for the fixed set.
func CompareAlerts(baselineAlerts []*ts.PhysicalAlert, alerts []*ts.PhysicalAlert) (AlertDiff, AlertDiff) {
	var openAlerts []*ts.PhysicalAlert
	var fixedAlerts []*ts.PhysicalAlert
	for _, a := range baselineAlerts {
		if a.IsFixed {
			fixedAlerts = append(fixedAlerts, a)
		} else {
			openAlerts = append(openAlerts, a)
		}
	}

	openDiff := compareAlerts(openAlerts, alerts)
	fixedDiff := compareAlerts(fixedAlerts, alerts)

	return openDiff, fixedDiff
}

// CompareAlertsMetadata will compare the two set of alerts and return the alerts where physical alert metadata fields changed
// This is used in addition to detecting the new/removed alerts, and finds alerts that are still there but changed
// The fields we are interested in are the fields that flow into logical alert in ES and are used by serializeSearchDocumentForInsights
// See SearchDocumentsFromAlerts for how fields are populated in ES from logical/physical alerts
func CompareAlertsMetadata(baselineAlerts []*ts.PhysicalAlert, alerts []*ts.PhysicalAlert) []*ts.PhysicalAlert {

	res := []*ts.PhysicalAlert{}

	// Find most recent physical alert for each logical alert
	baselineLogicalAlertsSet := make(map[ts.LogicalAlertID]*ts.PhysicalAlert)
	for _, a := range baselineAlerts {
		if _, ok := baselineLogicalAlertsSet[a.LogicalAlertID]; !ok {
			baselineLogicalAlertsSet[a.LogicalAlertID] = a
		} else if a.UpdatedAt.After(baselineLogicalAlertsSet[a.LogicalAlertID].UpdatedAt.Time) {
			baselineLogicalAlertsSet[a.LogicalAlertID] = a
		}
	}

	// Check the difference in fields that are important to logical alert and serializeSearchDocumentForInsights
	for _, a := range alerts {
		baselineAlert, ok := baselineLogicalAlertsSet[a.LogicalAlertID]
		if !ok {
			// This means new alert, which is already handled by CompareAlerts, as it is missing from baseline
			continue
		}

		// Changes to following fields are handled elsewhere:
		// FixedOnDefault will change only if physical alert is added/removed, which is handled by CompareAlerts
		// Resoution is changed by UI/API, so analysis upload won't change it

		if !equalSeverity(baselineAlert.SecuritySeverity, a.SecuritySeverity) ||
			baselineAlert.Analysis.ToolID != a.Analysis.ToolID || // Populates ToolName
			baselineAlert.RuleID != a.RuleID { // Populates RuleName and RuleSarifIdentifier
			res = append(res, a)
		}
	}

	return res
}

// equalSeverity returns true iff the two pointers represents the same severity
func equalSeverity(s1 *float64, s2 *float64) bool {
	if s1 == nil {
		return s2 == nil
	}
	if s2 == nil {
		return s1 == nil
	}
	return *s1 == *s2
}
