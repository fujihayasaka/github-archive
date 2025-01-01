import {OnboardingVideoBanner} from '../OnboardingVideoBanner'
import {onboardingVideoUrl} from '../../../../constants'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

const onDismiss = jest.fn().mockName('onDismiss')

describe('OnboardingVideoBanner', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders the banner view', async () => {
    const {user} = render(<OnboardingVideoBanner onDismiss={onDismiss} />)
    expect(screen.getByText('Watch the models demo')).toBeInTheDocument()
    expect(
      screen.getByText('Watch this 3-minute demo reel to learn everything you can do with GitHub Models'),
    ).toBeInTheDocument()
    const closeButton = screen.getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(onDismiss).not.toHaveBeenCalled()

    await user.click(closeButton)

    expect(onDismiss).toHaveBeenCalledTimes(1)
  })

  test('takes the user to GH models onboarding video link when the video image is clicked', async () => {
    const {user} = render(<OnboardingVideoBanner onDismiss={onDismiss} />)

    const linkElement = screen.getByRole('link', {name: 'play-button onboarding-video'})
    await user.click(linkElement)
    expect(linkElement.getAttribute('href')).toBe(onboardingVideoUrl)
  })
})
