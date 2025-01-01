import type {CustomCopilotGitHubFileResource, CustomCopilotResource} from '@github-ui/custom-copilots/types'
import {repositoryTreePath} from '@github-ui/paths'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useMemo} from 'react'

import {COPILOT_SPACES_PATH} from './copilot-chat-helpers'
import type {CopilotChatThread, CustomCopilot, CustomCopilotId} from './copilot-chat-types'

export const MANAGE_CUSTOM_COPILOTS_URL = '/custom_copilots'
export const CREATE_CUSTOM_COPILOTS_URL = '/custom_copilots/new'
export const SLUG_ERROR_MESSAGE =
  'The name of this space is too close to another existing space. Please modify the name and try again.'

/**
 * Returns a path for showing an individual space.
 */
export function getCopilotSpacePath(space: CustomCopilotId) {
  const {id, owner} = space
  if (owner) {
    return `${COPILOT_SPACES_PATH}/${owner}/${id}`
  }
  return `${COPILOT_SPACES_PATH}/${id}`
}

export function isCopilotSpacesCreatePath() {
  const path = ssrSafeLocation?.pathname

  return path === `${COPILOT_SPACES_PATH}/new`
}

/**
 * Returns true for both /copilot/spaces/:id/edit and /copilot/spaces/:owner/:id/edit style paths
 * @returns true if the current path matches the defined space path formats
 */
export function isCopilotSpaceEditPath() {
  // Matches /copilot/spaces/:space_id/edit where space_id is numeric
  const spaceIdPathRegex = new RegExp(`^${COPILOT_SPACES_PATH}/[0-9]+/edit$`)
  // Matches /copilot/spaces/:owner/:number/edit where owner is alphanumeric and number is numeric
  const spaceOwnerPathRegex = new RegExp(`^${COPILOT_SPACES_PATH}/[a-zA-Z0-9-]+/[0-9]+/edit$`)
  const isSpacePath =
    ssrSafeLocation?.pathname?.match(spaceIdPathRegex) || ssrSafeLocation?.pathname?.match(spaceOwnerPathRegex)

  return Boolean(isSpacePath)
}

/**
 * Returns a path for showing the edit page for individual space.
 */
export function getCopilotSpaceEditPath(space: CustomCopilotId) {
  return `${getCopilotSpacePath(space)}/edit`
}

export function isCopilotSpacesListPath() {
  const path = ssrSafeLocation?.pathname

  return path === COPILOT_SPACES_PATH || path === `${COPILOT_SPACES_PATH}/`
}

/**
 * Returns true for both /copilot/spaces/:id and /copilot/spaces/:owner/:id style paths
 * @returns true if the current path matches the defined space path formats
 */
export function isCopilotSpacePath() {
  // Matches /copilot/spaces/:space_id where space_id is numeric
  const spaceIdPathRegex = new RegExp(`^${COPILOT_SPACES_PATH}/[0-9]+$`)
  // Matches /copilot/spaces/:owner/:number where owner is alphanumeric and number is numeric
  const spaceOwnerPathRegex = new RegExp(`^${COPILOT_SPACES_PATH}/[a-zA-Z0-9-]+/[0-9]+$`)
  const isSpacePath =
    ssrSafeLocation?.pathname?.match(spaceIdPathRegex) || ssrSafeLocation?.pathname?.match(spaceOwnerPathRegex)

  return Boolean(isSpacePath)
}

/**
 *
 * @returns true if the current path is a copilot space path or a copilot spaces list path
 */
export function isCopilotSpacesPage() {
  return isCopilotSpacesListPath() || isCopilotSpacePath()
}

/**
 * Parses the space ID from the current URL and returns it.
 * We have to rely on the URL from the browser history because the space ID in the React Router state may be stale
 * since we manually push a history entry when creating a new thread and don't perform a navigation.
 */
export function useRouteSpaceId(): CustomCopilotId | null {
  const pathname = ssrSafeLocation.pathname

  return useMemo(() => {
    // Match /copilot/spaces/:owner/:number format
    const ownerMatch = pathname.match(/\/copilot\/spaces\/([^/]+)\/([^/]+)/)
    if (ownerMatch) {
      const [, owner, spaceId] = ownerMatch
      if (owner && spaceId) {
        const id = parseInt(spaceId, 10)
        if (!isNaN(id)) return {id, owner}
      }
      return null
    }

    // Match /copilot/spaces/:space_id format
    const idMatch = pathname.match(/\/copilot\/spaces\/([^/]+)/)
    if (idMatch) {
      const [, spaceId] = idMatch
      if (spaceId) {
        const id = parseInt(spaceId, 10)
        if (!isNaN(id)) return {id}
      }
      return null
    }

    return null
  }, [pathname])
}

export function customCopilotIdFromThread(thread?: CopilotChatThread | null): CustomCopilotId | null {
  if (!thread || !thread.customCopilotID) return null

  return {
    id: thread.customCopilotID,
    ...(thread.customCopilotOwner && {owner: thread.customCopilotOwner}),
  }
}

/**
 * Checks if a custom copilot matches the provided copilot ID.
 * @param customCopilot - The custom copilot to check
 * @param customCopilotId - The ID to match against
 * @returns True if the copilot matches the ID, false otherwise
 *
 * If customCopilotId has an owner property:
 * - Returns true if both ID and owner match
 * If customCopilotId has no owner:
 * - Returns true if ID matches the oldId
 */
export function customCopilotMatchesId(
  customCopilot: Pick<CustomCopilot, 'id' | 'owner' | 'oldId'>,
  customCopilotId: CustomCopilotId,
): boolean {
  if (customCopilotId.owner) {
    return customCopilot.id === customCopilotId.id && customCopilot.owner === customCopilotId.owner
  }
  return customCopilot.oldId === customCopilotId.id
}

/**
 * If customCopilotId.owner is not set, don't consider custom copilots that
 * have an owner defined.
 */
export function findCustomCopilot<T extends Pick<CustomCopilot, 'id' | 'owner' | 'oldId'>>(
  customCopilots?: T[],
  customCopilotId?: CustomCopilotId | null,
): T | undefined {
  if (!customCopilotId) return undefined
  return customCopilots?.find(copilot => customCopilotMatchesId(copilot, customCopilotId))
}

/**
 * Consolidates logic for generating the custom copilot path as we move to the new URL structure
 * This uses the old rails routes if the custom copilot hasn't been migrated yet.
 * If CustomCopilotId is null it returns a path appropriate for POST requests
 */
export function customCopilotApiPath(id?: Partial<CustomCopilotId> | null): string {
  if (!id || !id.id) return COPILOT_SPACES_PATH
  return id.owner ? `${COPILOT_SPACES_PATH}/${id.owner}/${id.id}` : `/custom_copilots/${id.id}`
}

export function getRepositoryFromOrgSearchQuery(org: string, queryString: string) {
  const orgIndexSplit = queryString.indexOf('/')

  // If there is no / in the query, or the org name is empty, just search for the repo name
  if (orgIndexSplit === -1 || orgIndexSplit === 0) {
    return `org:${org} ${queryString} in:name archived:false`
  }

  // Naively extract the org name and repo name from the query by assuming anything before the / is the org name
  const repoSearchName = queryString.slice(orgIndexSplit + 1)

  if (repoSearchName.length === 0) {
    return `org:${org} in:name archived:false`
  }

  return `org:${org} ${repoSearchName} in:name archived:false`
}

/**
 * Checks if the custom copilot size percentage is greater than 100
 * @param customCopilot
 * @returns true if the custom copilot has exceeded the size limit
 */
export function spaceSizeExceeded(customCopilot: CustomCopilot | undefined): boolean {
  return (customCopilot?.sizePercentage ?? 0) > 100
}

/**
 * NOT USED at the moment
 * Creates an event handler that prevents event propagation.
 * Used for custom copilot components to avoid triggering default behaviors.
 * @param handler The original event handler function
 * @returns A wrapped handler that stops propagation before executing the original handler
 */
export const createPropagationStoppingHandler =
  <T extends Event>(handler: (e: T) => void) =>
  (e: T) => {
    e.stopPropagation()
    handler(e)
  }

export function generateGitHubFileMetadata(resource: CustomCopilotGitHubFileResource) {
  const path = resource.filePath.split('/')
  const fileName = path.pop()!
  const filePath = [resource.nwo, ...path].join('/')
  const nwo = resource.nwo.split('/')
  const fileUrl =
    resource.fileExists && resource.commitish
      ? repositoryTreePath({
          repo: {ownerLogin: nwo[0]!, name: nwo[1]!},
          commitish: resource.commitish,
          action: 'blob',
          path: resource.filePath,
        })
      : undefined

  return {
    filePath,
    fileName,
    fileUrl,
  }
}

export function isIssueOrPrResource(resource: CustomCopilotResource) {
  return resource.type === 'github_issue' || resource.type === 'github_pull_request'
}
