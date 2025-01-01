import {updateUrlHash} from '@github-ui/history'
import type {LineRange} from '../types'
import {ssrSafeLocation} from '@github-ui/ssr-utils'

/**
 * Detect if location Hash matches a diff anchor with line numbers
 */
export function matchHash(hash: string): RegExpMatchArray | null {
  const diffAnchorMatch = hash.match(/^#?(diff-[a-f0-9]+)(L|R)(\d+)(?:-(L|R)(\d+))?$/i)
  if (diffAnchorMatch != null && diffAnchorMatch.length === 6) {
    return diffAnchorMatch
  }

  const discussionAnchorMatch = hash.match(/^#?(discussion-diff-[0-9]+)(L|R)(\d+)(?:-(L|R)(\d+))?$/i)
  if (discussionAnchorMatch != null && discussionAnchorMatch.length === 6) {
    return discussionAnchorMatch
  }

  return null
}

function lineHashFragmentFrom(lineNumber: number, orientation: 'left' | 'right'): string {
  return `${orientation === 'left' ? 'L' : 'R'}${lineNumber}`
}

export function parseDiffHash(hash: string): string | undefined {
  const diffMatch = hash.match(/^#?(diff-[a-f0-9]+)/)
  return diffMatch?.[1]
}

/*
 * Given a valid diff anchor string, returns whether it is a line or range selection
 */
export function isSelectingDiffLineOrRange(hash: string): boolean {
  // Validate that given hash matches our diff anchor with line numbers format
  if (!(matchHash(hash) || matchHash(`diff-${hash}`))) return false
  return hash.includes('R') || hash.includes('L')
}

/*
 * Given a valid diff anchor string, return the path digest (no anchor tag, no prefix, no line numbers)
 */
export function parsePathDigestWithoutLineNumbers(hash: string): string | undefined {
  // Validate that given hash matches our diff anchor format
  if (!(parseDiffHash(hash) || parseDiffHash(`diff-${hash}`))) return

  let pathDigest = hash.replace('#', '').replace('diff-', '')

  // Handle line ranges
  if (pathDigest.includes('-')) {
    pathDigest = pathDigest.split('-')[0] ?? ''
  }

  if (pathDigest.includes('L')) {
    pathDigest = pathDigest.split('L')[0] ?? ''
  }

  if (pathDigest.includes('R')) {
    pathDigest = pathDigest.split('R')[0] ?? ''
  }

  return pathDigest
}

/**
 *
 * Check if we're specifying a comment in the hash.
 * This format is defined in
 * [Platform::Models::PullRequestReviewComment#async_current_diff_path_uri](https://github.com/github/github/blob/420ce06f085acf1c9fd9d8948472b3fcca3ba467/packages/pull_requests/app/models/pull_request_review_comment.rb#L571)
 *
 * Basically `#r<database-id>`
 */
export function parseCommentHash(hash: string): number | undefined {
  const resourceMatch = hash.match(/^#?(r\d+)/)
  // coerce the match to a number if it exists
  const commentId = resourceMatch?.[1]

  if (commentId) {
    return parseInt(commentId.slice(1))
  } else {
    return undefined
  }
}

export function parseAnnotationHash(hash: string): number | undefined {
  const resourceMatch = hash.match(/^#annotation_(\d+)/)
  const annotationId = resourceMatch?.[1]

  if (annotationId) {
    return parseInt(annotationId)
  } else {
    return undefined
  }
}

/**
 * Returns the LineRange from the given hash
 *
 * @param hash e.g. #diff-146c1d65b0054fb45053c61a749f7cd421c4e62fdce49e86470aa9d7c32052ccR21-R25
 * @returns LineRange | undefined
 */
export function parseLineRangeHash(hash: string): LineRange | undefined {
  const match = matchHash(hash)
  if (match) {
    // match[0] is the full match so start at 1
    const diffAnchor = match[1]

    // start of range
    const startOrientation = match[2] ? (match[2] === 'L' ? 'left' : 'right') : undefined
    const startLineNumber = match[3] ? parseInt(match[3]) : undefined

    if (!diffAnchor || !startOrientation || startLineNumber === undefined) return undefined

    // end of range
    const endOrientation = match[4] ? (match[4] === 'L' ? 'left' : 'right') : undefined
    const endLineNumber = match[5] ? parseInt(match[5]) : undefined

    return {
      diffAnchor,
      startOrientation,
      startLineNumber,
      endOrientation: endOrientation ?? startOrientation,
      endLineNumber: endLineNumber ?? startLineNumber,
      firstSelectedLineNumber: startLineNumber,
      firstSelectedOrientation: startOrientation,
    }
  }
}

export function updateURLHashFromLineRange(lineRange: LineRange) {
  const newHash = urlHashFromLineRange(lineRange)
  updateURLHash(newHash)
}

export function urlHashFromLineRange(lineRange: LineRange) {
  const lineStartFragment = lineHashFragmentFrom(lineRange.startLineNumber, lineRange.startOrientation)
  let newHash = `${lineRange.diffAnchor}${lineStartFragment}`
  if (
    lineRange.endLineNumber !== lineRange.startLineNumber ||
    lineRange.endOrientation !== lineRange.startOrientation
  ) {
    const lineEndFragment = lineHashFragmentFrom(lineRange.endLineNumber, lineRange.endOrientation)
    newHash += `-${lineEndFragment}`
  }

  return newHash
}

export function updateURLHash(hash: string) {
  const newHash = `#${hash}`
  if (newHash === window.location.hash) return

  const oldURL = window.location.href
  updateUrlHash(newHash)
  window.dispatchEvent(
    new HashChangeEvent('hashchange', {
      newURL: window.location.href,
      oldURL,
    }),
  )
}
export const clearURLHash = () => updateURLHash('')

/**
 * Extracts the full diff hash from the current window URL.
 *
 * This function examines the URL hash and attempts to extract a diff identifier.
 * It first tries to match the hash against the pattern for line selections
 * using `matchHash()`. If that fails, it falls back to looking for just a diff
 * identifier using `parseDiffHash()`.
 *
 * The function returns the diff hash with any prefix ('diff-' or '#') removed.
 * Line numbers will be included in the return if present in the string
 *
 * @returns {string} The full diff hash from the URL without prefixes, or an empty string if none exists
 */
export function getSelectedFullDiffHash() {
  const windowHash = matchHash(ssrSafeLocation.hash ?? '') ?? ''
  let hashToUse = ''
  if (windowHash === '') {
    hashToUse = parseDiffHash(ssrSafeLocation.hash ?? '') ?? ''
  } else {
    hashToUse = windowHash?.[0] ?? ''
  }

  return hashToUse.replace('#', '').replace('diff-', '')
}
