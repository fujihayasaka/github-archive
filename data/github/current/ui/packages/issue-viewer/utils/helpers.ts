import {isFeatureEnabled} from '@github-ui/feature-flags'

export function getIssueTitle(title: string, titleHTML: string): string {
  const prohibitFallback = isFeatureEnabled('issues_react_prohibit_title_fallback')
  if (prohibitFallback) {
    return titleHTML
  }
  return titleHTML || title
}

// copied from: ui/packages/sub-issues/utils/urls.ts
export const QUERY_FIELDS = {
  label: 'label',
  type: 'type',
  assignee: 'assignee',
} as const
// Returns the repository "scoped" issues search url for the provided metadata
// For example, this is used to generate the search url used when clicking on an issue type token
export const getIssueSearchURL = (
  {owner, repo}: {owner: string; repo: string},
  field: keyof typeof QUERY_FIELDS,
  value: string,
) => {
  if (!owner || !repo) {
    return ''
  }

  const baseUrl = `/${owner}/${repo}/issues`

  if (!field || !value) {
    return baseUrl
  }

  value = value.includes(' ') ? `"${value}"` : value
  const query = encodeURIComponent(`${field}:${value}`)
  return `${baseUrl}?q=${query}`
}
