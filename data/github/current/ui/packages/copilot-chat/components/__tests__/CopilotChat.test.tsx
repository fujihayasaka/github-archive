import {render} from '@github-ui/react-core/test-utils'
import {fireEvent, screen, within} from '@testing-library/react'

import {CopilotChat} from '../../CopilotChat'
import {getCopilotChatProps} from '../../test-utils/mock-data'
import {copilotChatHeaderButtonID, copilotChatPanelInnerID} from '../../utils/constants'
import {copilotFeatureFlags} from '../../utils/copilot-feature-flags'

let mockEntryPointId = copilotChatHeaderButtonID
jest.mock('../../utils/CopilotChatContext', () => {
  const actual = jest.requireActual('../../utils/CopilotChatContext')
  return {
    ...actual,
    useChatState: () => {
      return {
        // eslint-disable-next-line @typescript-eslint/no-unsafe-call
        ...actual.useChatState(),
        entryPointId: mockEntryPointId,
      }
    },
  }
})

beforeEach(() => {
  // We utilize service workers to fuzy search references in Copilot Chat
  // when they are not available we show a warning to the user.
  // Workers are not available in JSDOM so we need to mock the console.warn.
  jest.spyOn(console, 'warn').mockImplementation()
})

test('Renders the CopilotChat', () => {
  const props = getCopilotChatProps()

  render(<CopilotChat {...props} />)

  const button = screen.getByTestId('copilot-chat-button')
  expect(button).toBeInTheDocument()
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button)

  expect(screen.getByTestId(copilotChatPanelInnerID)).toBeInTheDocument()
})

test('Renders the popover CTA when renderPopover is true', () => {
  const props = getCopilotChatProps()

  render(<CopilotChat {...props} renderPopover />)

  // look for the popover CTA
  const popover = screen.getByTestId('copilot-chat-cta-popover')
  expect(popover).toBeVisible()

  expect(within(popover).getByRole('button', {name: 'Got it!'})).toBeVisible()
})

test('Does not render the popover CTA when renderPopover is false', () => {
  const props = getCopilotChatProps()

  render(<CopilotChat {...props} renderPopover={false} />)

  // look for the popover CTA
  const popover = screen.queryByTestId('copilot-chat-cta-popover')
  expect(popover).not.toBeVisible()
})

describe('when task oriented assistive prototype available', () => {
  beforeEach(() => {
    mockEntryPointId = 'copilot-task-oriented-assistive'
    jest.spyOn(copilotFeatureFlags, 'taskOrientedAssistive', 'get').mockReturnValue(true)
  })

  test('Renders task-oriented assistive prototype', async () => {
    const props = getCopilotChatProps()

    const {user} = render(<CopilotChat {...props} />)

    const button = screen.getByTestId('copilot-chat-button')
    expect(button).toBeInTheDocument()
    await user.click(button)

    expect(screen.queryByTestId(copilotChatPanelInnerID)).not.toBeInTheDocument()
    expect(screen.getByTestId('copilot-assistive-command-window')).toBeInTheDocument()
  })

  test('Renders the popover CTA when renderPopover is true', () => {
    const props = getCopilotChatProps()

    render(<CopilotChat {...props} renderPopover />)

    // look for the popover CTA
    const popover = screen.getByTestId('copilot-chat-cta-popover')
    expect(popover).toBeVisible()

    expect(within(popover).getByRole('button', {name: 'Got it!'})).toBeVisible()
  })

  test('Does not render the popover CTA when renderPopover is false', () => {
    const props = getCopilotChatProps()

    render(<CopilotChat {...props} renderPopover={false} />)

    // look for the popover CTA
    const popover = screen.queryByTestId('copilot-chat-cta-popover')
    expect(popover).not.toBeVisible()
  })
})
