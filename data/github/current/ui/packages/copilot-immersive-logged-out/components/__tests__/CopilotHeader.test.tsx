import {render} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {screen} from '@testing-library/react'

import {SIGN_IN_PATH, SIGN_UP_PATH} from '../../test-utils/helpers'
import {mockCopilotImmersiveLoggedOutPayload} from '../../test-utils/mock-data'
import {CopilotHeader} from '../CopilotHeader'

jest.mock('@github-ui/react-core/use-app-payload')

describe('CopilotHeader', () => {
  it('renders the component with links', () => {
    jest.mocked(useAppPayload).mockReturnValue(mockCopilotImmersiveLoggedOutPayload)

    render(<CopilotHeader />)

    expect(screen.getByText(/Copilot/i)).toBeInTheDocument()

    const signInLink = screen.getByRole('link', {name: /Sign In/i})
    const signUpLink = screen.getByRole('link', {name: /Sign Up/i})

    expect(signInLink).toHaveAttribute('href', SIGN_IN_PATH)
    expect(signUpLink).toHaveAttribute('href', SIGN_UP_PATH)
  })
})
