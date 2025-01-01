import {render} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {screen} from '@testing-library/react'

import App from '../../App'
import CopilotImmersiveLoggedOut from '../../routes/CopilotImmersiveLoggedOut'
import {SIGN_IN_PATH, SIGN_UP_PATH} from '../../test-utils/helpers'
import {mockCopilotImmersiveLoggedOutPayload} from '../../test-utils/mock-data'

jest.mock('@github-ui/react-core/use-app-payload')

function TestComponent() {
  return (
    <App>
      <CopilotImmersiveLoggedOut />
    </App>
  )
}

describe('CopilotImmersiveLoggedOut', () => {
  it('renders', () => {
    jest.mocked(useAppPayload).mockReturnValue(mockCopilotImmersiveLoggedOutPayload)

    render(<TestComponent />)

    const signInLink = screen.getByRole('link', {name: /Sign In/})
    const signUpLink = screen.getByRole('link', {name: /Sign Up/})

    expect(signInLink).toHaveAttribute('href', SIGN_IN_PATH)
    expect(signUpLink).toHaveAttribute('href', SIGN_UP_PATH)
  })
})
