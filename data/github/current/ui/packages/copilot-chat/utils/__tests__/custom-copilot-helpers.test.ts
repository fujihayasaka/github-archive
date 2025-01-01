import {ssrSafeLocation} from '@github-ui/ssr-utils'

import type {CustomCopilot} from '../copilot-chat-types'
import {copilotFeatureFlags} from '../copilot-feature-flags'
import {getCopilotSpacePath, isValidCopilotSpacePath} from '../custom-copilots-helpers'

interface SsrSafeLocation {
  pathname: string
}

interface CopilotFeatureFlags {
  customCopilots: boolean
}

// Mock all the dependencies
jest.mock('@github-ui/use-navigate')
jest.mock('@github-ui/ssr-utils', () => ({
  ssrSafeLocation: {
    pathname: '',
  },
}))
jest.mock('@github-ui/copilot-chat/utils/copilot-feature-flags', () => ({
  copilotFeatureFlags: {
    customCopilots: true,
  },
}))
jest.mock('@github-ui/copilot-chat/utils/CopilotChatManagerContext')
jest.mock('@github-ui/copilot-chat/utils/CopilotChatContext')

beforeEach(() => {
  jest.clearAllMocks()
})

describe('isValidCopilotSpacePath', () => {
  const copilotSpacesPath = getCopilotSpacePath(1)
  const customCopilots: CustomCopilot[] = [
    {
      id: 1,
      name: 'Test Copilot',
      slug: '',
      primaryAvatarPath: '',
      updatedAt: '',
      slugWithOwner: '',
      description: '',
      resources: [],
      generalInstructions: '',
    },
  ]

  beforeEach(() => {
    // Set up the location mock to be on spaces path
    ;(ssrSafeLocation as SsrSafeLocation).pathname = copilotSpacesPath
  })

  it('returns false when not on spaces path', () => {
    // Set up the location mock
    ;(ssrSafeLocation as SsrSafeLocation).pathname = '/some-other-path'

    const customCopilotId = 1
    const result = isValidCopilotSpacePath(customCopilots, customCopilotId)

    expect(result).toBe(false)
  })

  it('returns true when selected space exists in the list', () => {
    const result = isValidCopilotSpacePath(customCopilots, 1)

    expect(result).toBe(true)
  })

  it('returns false when selected space does not exist in the list', () => {
    const result = isValidCopilotSpacePath(customCopilots, 2)

    expect(result).toBe(false)
  })

  it('returns false when feature flag is disabled', () => {
    // Disable the feature flag
    ;(copilotFeatureFlags as CopilotFeatureFlags).customCopilots = false

    const result = isValidCopilotSpacePath(customCopilots, 1)

    expect(result).toBe(false)

    // Reset the feature flag
    ;(copilotFeatureFlags as CopilotFeatureFlags).customCopilots = true
  })

  it('returns false when no space is selected', () => {
    const result = isValidCopilotSpacePath(customCopilots, null)

    expect(result).toBe(false)
  })
})
