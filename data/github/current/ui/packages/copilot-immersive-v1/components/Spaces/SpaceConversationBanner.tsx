import type {CustomCopilot, CustomCopilotId} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {spaceSizeExceeded} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {
  CustomCopilotNotFoundError,
  CustomCopilotSSOError,
  useFetchCustomCopilot,
} from '@github-ui/custom-copilots/hooks'

import {SpaceDeletedBanner, SpaceSizeExceededBanner} from './SpaceBanners'

export const spaceConversationVariants = {
  spaceHomepage: 'spaceHomepage',
  customCopilotDisabled: 'customCopilotDisabled',
  customCopilotSizeExceeded: 'customCopilotSizeExceeded',
} as const

type SpaceConversationVariant = keyof typeof spaceConversationVariants

export function spaceConversationVariant(
  customCopilotId: CustomCopilotId | null | undefined,
  customCopilot: CustomCopilot | undefined,
  isPending: boolean,
  threadId: string | null,
): SpaceConversationVariant | null {
  const isSpaceHomepage = customCopilotId && !threadId
  if (isSpaceHomepage) {
    return spaceConversationVariants.spaceHomepage
  }

  if (isPending) {
    return null
  }

  const customCopilotExists = Boolean(customCopilot)
  // If we requested a specific copilot but it doesn't exist after loading, it's considered disabled/not found.
  const customCopilotDisabled = !!customCopilotId && !customCopilotExists
  if (customCopilotDisabled) {
    return spaceConversationVariants.customCopilotDisabled
  }
  const customCopilotSizeExceed = spaceSizeExceeded(customCopilot)
  if (customCopilotSizeExceed) {
    return spaceConversationVariants.customCopilotSizeExceeded
  }
  return null
}

export function SpaceConversationBanner({
  variant,
  customCopilot,
}: {
  variant: SpaceConversationVariant
  customCopilot: CustomCopilot | undefined
}) {
  switch (variant) {
    case spaceConversationVariants.customCopilotDisabled:
      return <SpaceDeletedBanner />
    case spaceConversationVariants.customCopilotSizeExceeded:
      return <SpaceSizeExceededBanner customCopilot={customCopilot} />
    case spaceConversationVariants.spaceHomepage:
      return <></>
    default:
      return null
  }
}

type SpaceConversationStatus = {
  variant: keyof typeof spaceConversationVariants | null
  customCopilot: CustomCopilot | undefined
  isLoading: boolean
}

export function useSpaceConversationStatus(
  customCopilotId: CustomCopilotId | null,
  threadId: string | null,
): SpaceConversationStatus {
  const customCopilotQuery = useFetchCustomCopilot(customCopilotId)
  const {isPending, data: customCopilotPayload, error} = customCopilotQuery

  const notFound = error instanceof CustomCopilotNotFoundError
  const notSSO = error instanceof CustomCopilotSSOError
  if (error && !notFound && !notSSO) {
    // Other errors are truly exceptional and should be handled by the error boundary.
    throw error
  }
  const customCopilot = !isPending && !notFound && !notSSO && customCopilotPayload ? customCopilotPayload : undefined

  const variant = spaceConversationVariant(customCopilotId, customCopilot, isPending, threadId)

  return {
    variant,
    customCopilot,
    isLoading: isPending,
  }
}
