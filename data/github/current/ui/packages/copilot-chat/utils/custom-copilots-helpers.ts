import {useQuery} from '@github-ui/react-query'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useCallback} from 'react'

import {COPILOT_SPACES_PATH, findAgentCorrespondents} from './copilot-chat-helpers'
import type {CopilotChatAgent, CustomCopilot} from './copilot-chat-types'
import {copilotFeatureFlags} from './copilot-feature-flags'
import {useChatState} from './CopilotChatContext'
import {useChatManager} from './CopilotChatManagerContext'

export const MANAGE_CUSTOM_COPILOTS_URL = '/custom_copilots'
export const CREATE_CUSTOM_COPILOTS_URL = '/custom_copilots/new'

/**
 * @param enabled Set to true when the custom copilots list is rendered (ie, the menu is open). This enables lazy fetching. If
 * always true, will start fetching as soon as the consuming component is mounted.
 */
export function useAvailableCustomCopilots(enabled = true) {
  const {model, messages} = useChatState()
  const manager = useChatManager()
  const customCopilotsEnabled = copilotFeatureFlags.customCopilots

  const unsupportedModel = model?.hasLimitedCapabilities
  const selectCopilots = useCallback(
    (copilots: CustomCopilot[]) => {
      if (!customCopilotsEnabled || unsupportedModel) return {copilots: [], showLimit: false}

      const previousAgent = findAgentCorrespondents(messages)[0]
      if (previousAgent)
        return {
          copilots: copilots.filter(agent => agent.slugWithOwner === previousAgent.name),
          showLimit: true,
        }

      return {copilots, showLimit: false}
    },
    [customCopilotsEnabled, messages, unsupportedModel],
  )

  const {isLoading, data, refetch, isStale, isFetched} = useQuery({
    queryKey: ['copilot-chat', 'custom-copilots'],
    queryFn: () => manager.fetchCustomCopilots(),
    select: selectCopilots,
    enabled,
  })

  /**
   * Imperatively fetch in a callback. This is not really how tanstack query is meant to be used but allows us to
   * lazily fetch when the button is clicked. We can delete this when we ship the unified attachment menu since we can
   * then just declaratively fetch when the menu is open.
   */
  const imperativelyFetch = useCallback(async () => {
    if (!isFetched || isStale) {
      const result = await refetch()
      return result.data
    }
    return data
  }, [data, isFetched, isStale, refetch])

  return {
    loading: isLoading,
    disabled: unsupportedModel,
    availableCopilots: data?.copilots,
    showLimit: data?.showLimit,
    imperativelyFetch,
  }
}

export function isCustomCopilot(extension: CopilotChatAgent | CustomCopilot): extension is CustomCopilot {
  const customCopilotsEnabled = copilotFeatureFlags.customCopilots

  if (!customCopilotsEnabled) return false
  return 'slugWithOwner' in extension
}

export function getCopilotSpacePath(spaceId: number) {
  return `${COPILOT_SPACES_PATH}/${spaceId}`
}

export function isCopilotSpacesListPath() {
  const path = ssrSafeLocation?.pathname

  return path === COPILOT_SPACES_PATH || path === `${COPILOT_SPACES_PATH}/`
}

export function isCopilotSpacePath() {
  const spacePathRegex = new RegExp(`^${COPILOT_SPACES_PATH}/[a-zA-Z0-9]+$`)
  const isSpacePath = ssrSafeLocation?.pathname?.match(spacePathRegex)

  return Boolean(isSpacePath)
}

export function isValidCopilotSpacePath(
  customCopilots: CustomCopilot[] | undefined,
  customCopilotId: number | null | undefined,
): boolean {
  const customCopilotsFlag = copilotFeatureFlags.customCopilots
  const isSelectedSpace = Boolean(customCopilotId) && Boolean(customCopilots)
  const existingSpace = customCopilots?.find(customCopilot => customCopilot.id === customCopilotId)

  return Boolean(customCopilotsFlag && isCopilotSpacePath() && isSelectedSpace && existingSpace)
}
