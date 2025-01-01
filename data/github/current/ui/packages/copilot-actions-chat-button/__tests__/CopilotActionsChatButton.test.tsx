import {fireEvent, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {CopilotActionsChatButton} from '../CopilotActionsChatButton'
import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'

jest.mock('@github-ui/copilot-chat/utils/copilot-chat-events', () => ({
  publishOpenCopilotChat: jest.fn(),
}))

afterEach(() => {
  jest.clearAllMocks()
})

test('renders the CopilotActionsChatButton', () => {
  render(<CopilotActionsChatButton />)
  expect(screen.getAllByText('Explain error')[1]).toBeInTheDocument()
})

test('publishes an event when clicked', () => {
  render(<CopilotActionsChatButton />)
  expect(screen.getAllByText('Explain error')[1]).toBeInTheDocument()
  const btn = screen.getAllByText('Explain error')[1]!
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(btn)
  expect(publishOpenCopilotChat).toHaveBeenCalledTimes(1)
})
