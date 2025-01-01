export function riskAssessmentPath(org: string) {
  return `/orgs/${org}/security/assessments`
}

export function riskAssessmentJsonPath(org: string) {
  return `/orgs/${org}/security/assessments/json`
}

export function downloadResultsCSVPath(org: string) {
  return `/orgs/${org}/security/assessments/results-csv.csv`
}

export function enableGhspPath(org: string) {
  return `/orgs/${org}/security/assessments/enable-ghsp`
}

export function hasConfigConflict(org: string) {
  return `/orgs/${org}/security/assessments/has-config-conflict`
}
