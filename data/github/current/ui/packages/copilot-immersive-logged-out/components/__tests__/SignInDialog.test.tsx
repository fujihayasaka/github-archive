import {render} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {screen} from '@testing-library/react'

import {copilotWrapper as wrapper} from '../../test-utils/helpers'
import {mockCopilotImmersiveLoggedOutPayload} from '../../test-utils/mock-data'
import {SignInDialog} from '../SignInDialog'

jest.mock('@github-ui/react-core/use-app-payload')

describe('SignInDialog', () => {
  const mockOnClose = () => {}

  test('renders dialog with correct content', () => {
    jest.mocked(useAppPayload).mockReturnValue(mockCopilotImmersiveLoggedOutPayload)

    render(<SignInDialog onClose={mockOnClose} />, {wrapper})

    expect(screen.getByText('Sign in to continue')).toBeInTheDocument()
    expect(screen.getByText('Sign in or create a GitHub account to continue using Copilot.')).toBeInTheDocument()
  })

  test('renders sign in and sign up buttons with correct form values', () => {
    jest.mocked(useAppPayload).mockReturnValue(mockCopilotImmersiveLoggedOutPayload)

    render(<SignInDialog onClose={mockOnClose} />, {wrapper})

    const signInButton = screen.getByRole('button', {name: 'Sign in'})
    expect(signInButton).toBeInTheDocument()

    const signUpButton = screen.getByRole('button', {name: 'Create a free account'})
    expect(signUpButton).toBeInTheDocument()
  })
})
