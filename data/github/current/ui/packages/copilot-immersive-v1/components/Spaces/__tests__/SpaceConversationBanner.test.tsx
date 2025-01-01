import {spaceSizeExceeded} from '@github-ui/copilot-chat/utils/custom-copilots-helpers'
import {getCustomCopilotMock} from '@github-ui/custom-copilots/test-utils/mock-data'

import {spaceConversationVariant, spaceConversationVariants} from '../SpaceConversationBanner'

// Use simpler jest.mock syntax
jest.mock('@github-ui/copilot-chat/utils/custom-copilots-helpers', () => ({
  spaceSizeExceeded: jest.fn(),
}))

const mockedSpaceSizeExceeded = spaceSizeExceeded as jest.MockedFunction<typeof spaceSizeExceeded>

describe('spaceConversationVariant', () => {
  // Mock payload with all required properties for CustomCopilotPayload
  const mockCopilot = getCustomCopilotMock({id: 42, owner: 'monalisa'})

  beforeEach(() => {
    mockedSpaceSizeExceeded.mockReset()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  it('returns spaceHomepage when customCopilotId is set and threadId is null', () => {
    expect(spaceConversationVariant({id: 42, owner: 'monalisa'}, mockCopilot, false, null)).toBe(
      spaceConversationVariants.spaceHomepage,
    )
  })

  it('returns null if query is pending', () => {
    expect(spaceConversationVariant({id: 42, owner: 'monalisa'}, undefined, true, 'thread')).toBeNull()
  })

  it('returns customCopilotDisabled if customCopilotId is set and copilot is undefined after loading', () => {
    expect(spaceConversationVariant({id: 42, owner: 'monalisa'}, undefined, false, 'thread')).toBe(
      spaceConversationVariants.customCopilotDisabled,
    )
  })

  it('returns customCopilotSizeExceeded if spaceSizeExceeded returns true', () => {
    mockedSpaceSizeExceeded.mockReturnValue(true)
    expect(spaceConversationVariant({id: 42, owner: 'monalisa'}, mockCopilot, false, 'thread')).toBe(
      spaceConversationVariants.customCopilotSizeExceeded,
    )
  })

  it('returns null if no special case matches', () => {
    mockedSpaceSizeExceeded.mockReturnValue(false)
    expect(spaceConversationVariant({id: 42, owner: 'monalisa'}, mockCopilot, false, 'thread')).toBeNull()
  })
})
