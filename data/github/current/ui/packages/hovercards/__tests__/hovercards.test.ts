import {hovercardAttributesForActor} from '../hovercards'

describe('hovercardAttributes', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('returns user hovercard attributes by default with tracking', () => {
    const login = 'testuser'
    const attributes = hovercardAttributesForActor(login)

    expect(attributes).toEqual({
      'data-hovercard-url': '/users/testuser/hovercard',
      'data-hovercard-type': 'user',
      'octo-click': 'hovercard-link-click',
      'octo-dimensions': 'link_type:self',
    })
  })

  it('returns user hovercard attributes without tracking when tracking is disabled', () => {
    const login = 'testuser'
    const attributes = hovercardAttributesForActor(login, {tracking: false})

    expect(attributes).toEqual({
      'data-hovercard-url': '/users/testuser/hovercard',
      'data-hovercard-type': 'user',
    })
  })

  it('returns copilot hovercard attributes with tracking when isCopilot is true', () => {
    const login = 'copilot'
    const attributes = hovercardAttributesForActor(login, {isCopilot: true})

    expect(attributes).toEqual({
      'data-hovercard-url': '/copilot/hovercard?bot=copilot',
      'data-hovercard-type': 'copilot',
      'octo-click': 'hovercard-link-click',
      'octo-dimensions': 'link_type:self',
    })
  })

  it('returns copilot hovercard attributes without tracking when tracking is disabled', () => {
    const login = 'copilot'
    const attributes = hovercardAttributesForActor(login, {isCopilot: true, tracking: false})

    expect(attributes).toEqual({
      'data-hovercard-url': '/copilot/hovercard?bot=copilot',
      'data-hovercard-type': 'copilot',
    })
  })
})
