import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {screen, within} from '@testing-library/react'

import {copilotWrapper as wrapper} from '../../test-utils/helpers'
import {mockCopilotImmersiveLoggedOutPayload} from '../../test-utils/mock-data'
import {ChatInput} from '../ChatInput'

const userEvent = setupUserEvent()

jest.mock('@github-ui/react-core/use-app-payload')

describe('ChatInput', () => {
  it('renders the component', () => {
    jest.mocked(useAppPayload).mockReturnValue(mockCopilotImmersiveLoggedOutPayload)

    render(<ChatInput />, {wrapper})
    expect(screen.getByPlaceholderText(/Ask Copilot/i)).toBeInTheDocument()
  })

  it('opens dialog with encoded when clicking send button', async () => {
    jest.mocked(useAppPayload).mockReturnValue(mockCopilotImmersiveLoggedOutPayload)

    render(<ChatInput />, {wrapper})

    const input = screen.getByPlaceholderText(/Ask Copilot/i)
    const sendButton = screen.getByRole('button', {name: 'Send now (enter)'})

    const message = 'test message'
    await userEvent.clear(input)
    await userEvent.type(input, message)
    await userEvent.click(sendButton)

    const dialog = screen.getByRole('dialog')
    expect(dialog).toBeInTheDocument()

    const signInButton = within(dialog).getByTestId('sign-in-button')
    expect(signInButton).toBeInTheDocument()

    const signUpButton = within(dialog).getByTestId('sign-up-button')
    expect(signUpButton).toBeInTheDocument()
  })
})
