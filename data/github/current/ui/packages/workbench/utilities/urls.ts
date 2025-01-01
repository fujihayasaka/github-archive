/**
 * Prefer useLocation() react routing hooks.
 * Rendertime tracking gets lost when using window.location directly.
 */

import {encodePart} from '@github-ui/paths'
import {initialPathQueryParam} from '@github-ui/workspace-editor/utilities/query-params'

/**
 * URL path for the app. Gets appended to a pull request URL.
 */
export const EDITOR_PATH = 'edit'

export function sparkUrl({sparkId}: {sparkId: string}) {
  return `/copilot/spark/${encodeURIComponent(sparkId)}`
}

// TODO: Using the Codespace GUID as a temporary unique identifier instead of the pull request number
export function baseUrl({owner, repo, codespaceId}: {owner: string; repo: string; codespaceId: string}) {
  return `/${encodeURIComponent(owner)}/${encodeURIComponent(repo)}/codespace/${codespaceId}`
}

export function baseEditUrl({owner, repo, codespaceId}: {owner: string; repo: string; codespaceId: string}) {
  return `${baseUrl({owner, repo, codespaceId})}/${EDITOR_PATH}`
}

export function overviewUrl({
  owner,
  repo,
  codespaceId,
  location,
}: {
  owner: string
  repo: string
  codespaceId: string
  location?: {search: string}
}) {
  const url = baseEditUrl({owner, repo, codespaceId})
  return url + (location?.search || '')
}

export function fileUrl({
  owner,
  repo,
  codespaceId,
  path,
  location,
}: {
  owner: string
  repo: string
  codespaceId: string
  path: string
  location?: {search: string}
}) {
  // encodePart splits by '/' and encodes the resulting parts so we don't uglify our path in the URL
  const url = `${baseEditUrl({owner, repo, codespaceId})}/file/${encodePart(path)}`
  return url + (location?.search || '')
}

export function lightweightFileUrl({
  sparkId,
  path,
  location,
}: {
  sparkId: string
  path: string
  location?: {search: string}
}) {
  const url = `${sparkUrl({sparkId})}/files/${encodeURIComponent(path)}`
  return url + (location?.search || '')
}

export function newFileUrl({
  owner,
  repo,
  codespaceId,
  location,
  path,
}: {
  owner: string
  repo: string
  codespaceId: string
  location?: {search: string}
  path?: string
}) {
  const url = `${baseEditUrl({owner, repo, codespaceId})}/new`
  const searchParams = new URLSearchParams(location?.search || '')
  if (path && path.includes('/')) {
    // Remove the file name from the current path
    const dirPath = path.substring(0, path.lastIndexOf('/') + 1)
    searchParams.set(initialPathQueryParam, dirPath)
  }
  const searchParamsString = searchParams.toString() ? `?${searchParams.toString()}` : ''
  return url + searchParamsString
}

export function commitChangesUrl({owner, repo, codespaceId}: {owner: string; repo: string; codespaceId: string}) {
  return `${baseEditUrl({owner, repo, codespaceId})}/commit_changes`
}

export function taskDiffUrl({
  owner,
  repo,
  codespaceId,
  analyzeDiffs = false,
  detectRisk = false,
}: {
  owner: string
  repo: string
  codespaceId: string
  analyzeDiffs?: boolean
  detectRisk?: boolean
}) {
  const base = `${baseUrl({owner, repo, codespaceId})}/diff`
  const params = new URLSearchParams({analyze_diffs: analyzeDiffs.toString(), detect_risk: detectRisk.toString()})
  return `${base}?${params.toString()}`
}

export function hadronFileUrl({
  owner,
  repo,
  path,
  pullNumber,
  location,
}: {
  owner: string
  repo: string
  pullNumber: string
  path: string
  location?: {search: string}
}) {
  const url = `/${encodeURIComponent(owner)}/${encodeURIComponent(
    repo,
  )}/workbench/${pullNumber}/${EDITOR_PATH}/file/${encodePart(path)}`
  return url + (location?.search || '')
}
