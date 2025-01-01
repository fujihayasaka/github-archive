package v210autofix

// SarifLog is a type alias for SARIF210ForGitHubAutofix
type SarifLog = SARIF210ForGitHubAutofix

// Equals compares two SarifLog values by ensuring the list of runs are equal.
func (sarifLog SarifLog) Equals(that SarifLog) bool {
	if len(sarifLog.Runs) != len(that.Runs) {
		return false
	}
	for i := range sarifLog.Runs {
		if !sarifLog.Runs[i].Equals(*that.Runs[i]) {
			return false
		}
	}
	return true
}
