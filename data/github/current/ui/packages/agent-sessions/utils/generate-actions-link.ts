// Generates links to GitHub Actions pages based on the provided parameters.
// Currently supports generating links for workflow runs
// TODO: Add support for links to specific job logs

export function generateWorkflowRunLink(
  ownerLogin: string,
  repoName: string,
  workflowRunId: number | null,
): string | undefined {
  if (ownerLogin == null || repoName == null || workflowRunId == null) {
    return undefined
  }

  return `/${ownerLogin}/${repoName}/actions/runs/${workflowRunId}`
}
