import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {sendEvent} from '@github-ui/hydro-analytics'
import {UseThisModelButton} from '../UseThisModelButton'
import {GettingStartedButtonClicked} from '../../utils/playground-types'
import {mockModel} from '../../routes/playground/__tests__/mocks'
import type {UserHookPayload} from '@github-ui/use-user'
import {mockUser} from '../../routes/playground/components/__tests__/mocks'

const onClick = jest.fn().mockName('onClick')

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: jest.fn(),
  }
})

const currentUser = Object.assign({}, mockUser, {analyticsTrackingId: '8675309'})
const appPayload: UserHookPayload = {current_user: currentUser}

describe('UseThisModelButton', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders', async () => {
    const {registry, name: modelName, publisher} = mockModel

    const {user} = render(<UseThisModelButton className="some-custom-class" model={mockModel} onClick={onClick} />, {
      appPayload,
    })

    const button = screen.getByRole('button', {name: 'Use this model'})
    expect(button).toBeInTheDocument()
    expect(button).toHaveClass('some-custom-class')
    expect(onClick).not.toHaveBeenCalled()
    expect(sendEvent).not.toHaveBeenCalled()

    await user.click(button)

    expect(onClick).toHaveBeenCalledTimes(1)
    expect(sendEvent).toHaveBeenCalledTimes(1)
    expect(sendEvent).toHaveBeenCalledWith(GettingStartedButtonClicked, {
      registry,
      model: modelName,
      publisher,
      label: 'Use this model',
      analyticsTrackingId: currentUser.analyticsTrackingId,
    })
  })
})
