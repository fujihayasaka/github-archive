/**
 * Prefer useLocation() react routing hooks.
 * Rendertime tracking gets lost when using window.location directly.
 */

import {encodePart} from '@github-ui/paths'

import {initialPathQueryParam} from './query-params'

/**
 * URL path for the app. Gets appended to a pull request URL.
 */
export const EDITOR_PATH = 'edit'

export function baseUrl({owner, repo, pullNumber}: {owner: string; repo: string; pullNumber: string}) {
  return `/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/pull/${pullNumber}`
}

export function baseEditUrl({owner, repo, pullNumber}: {owner: string; repo: string; pullNumber: string}) {
  return `${baseUrl({owner, repo, pullNumber})}/${EDITOR_PATH}`
}

export function overviewUrl({
  owner,
  repo,
  pullNumber,
  location,
}: {
  owner: string
  repo: string
  pullNumber: string
  location?: {search: string}
}) {
  const url = baseEditUrl({owner, repo, pullNumber})
  return url + (location?.search || '')
}

export function fileUrl({
  owner,
  repo,
  pullNumber,
  path,
  location,
}: {
  owner: string
  repo: string
  pullNumber: string
  path: string
  location?: {search: string}
}) {
  // encodePart splits by '/' and encodes the resulting parts so we don't uglify our path in the URL
  const url = `${baseEditUrl({owner, repo, pullNumber})}/file/${encodePart(path)}`
  return url + (location?.search || '')
}

export function suggestionsUrl({owner, repo, pullNumber}: {owner: string; repo: string; pullNumber: string}) {
  return `${baseUrl({owner, repo, pullNumber})}/workspace_editor/suggestions`
}

export function suggestionUrl({
  owner,
  repo,
  pullNumber,
  pullRequestReviewCommentId,
}: {
  owner: string
  repo: string
  pullNumber: string
  pullRequestReviewCommentId: string
}) {
  return `${baseUrl({owner, repo, pullNumber})}/workspace_editor/suggestions/${pullRequestReviewCommentId}`
}

export function lightweightFileUrl({
  commitOid,
  owner,
  repo,
  pullNumber,
  path,
  location,
}: {
  commitOid: string
  owner: string
  repo: string
  pullNumber: string
  path: string
  location?: {search: string}
}) {
  const url = `${baseUrl({owner, repo, pullNumber})}/workspace_editor/files/${encodeURIComponent(
    commitOid,
  )}/${encodeURIComponent(path)}`
  return url + (location?.search || '')
}

export function newFileUrl({
  owner,
  repo,
  pullNumber,
  location,
  path,
}: {
  owner: string
  repo: string
  pullNumber: string
  location?: {search: string}
  path?: string
}) {
  const url = `${baseEditUrl({owner, repo, pullNumber})}/new`
  const searchParams = new URLSearchParams(location?.search || '')
  if (path && path.includes('/')) {
    // Remove the file name from the current path
    const dirPath = path.substring(0, path.lastIndexOf('/') + 1)
    searchParams.set(initialPathQueryParam, dirPath)
  }
  const searchParamsString = searchParams.toString() ? `?${searchParams.toString()}` : ''
  return url + searchParamsString
}

export function commitChangesUrl({owner, repo, pullNumber}: {owner: string; repo: string; pullNumber: string}) {
  return `${baseEditUrl({owner, repo, pullNumber})}/commit_changes`
}

export function taskDiffUrl({
  owner,
  repo,
  pullNumber,
  analyzeDiffs = false,
  detectRisk = false,
}: {
  owner: string
  repo: string
  pullNumber: string
  analyzeDiffs?: boolean
  detectRisk?: boolean
}) {
  const base = `${baseUrl({owner, repo, pullNumber})}/diff`
  const params = new URLSearchParams({analyze_diffs: analyzeDiffs.toString(), detect_risk: detectRisk.toString()})
  return `${base}?${params.toString()}`
}
