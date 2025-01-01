package v210autofix

type SarifLog = SARIF210ForGitHubAutofix

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
