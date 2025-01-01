import type {PullRequest, DiffHunk, HydratedIssueReference} from './types'

export const getPrContext = (
  pullRequest: PullRequest,
  diffs: DiffHunk[],
  mentionedIssues: HydratedIssueReference[],
): string => {
  const context = `
  ## Pull Request
  Title: ${pullRequest.title} (#${pullRequest.number})
  Body:
  ${pullRequest.body}

  ## Mentioned Issues
  ${mentionedIssueContent(mentionedIssues)}
  `
  if (diffs.length === 0) {
    return context
  }

  return `
  ${context}
  ## Hunk Summaries
  ${getHunkSummaries(diffs)}
  `
}

function getHunkSummaries(diffHunks: DiffHunk[]) {
  const hunkSummaries = diffHunks.map(({hunkId, filePath, rawUnifiedDiff}) => ({
    hunkId: `HUNK:${hunkId}`,
    filePath,
    snippet: rawUnifiedDiff || '',
  }))
  return JSON.stringify(hunkSummaries, null, 2)
}

export const issueSummary = (issue: HydratedIssueReference) => `
  Title: ${issue.title} (#${issue.issueNumber})
  Body:
  ${issue.body}
  ---
  `

export const mentionedIssueContent = (mentionedIssues: HydratedIssueReference[]): string =>
  mentionedIssues.length === 0
    ? 'No issues are mentioned.'
    : `
  The following issues are mentioned in this pull request. They often indicate the intent or motivation for these changes. Use them to guide your groupings and descriptions:
  ${mentionedIssues.map(issueSummary).join('\n')}
  `
