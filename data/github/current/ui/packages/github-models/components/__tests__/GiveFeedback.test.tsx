import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {isFeatureEnabled} from '@github-ui/feature-flags'
import {GiveFeedback} from '../GiveFeedback'
import {feedbackUrl} from '../../constants'
import {mockShowModelPayload} from '../../routes/show/components/__tests__/mocks'
import {verifiedFetch} from '@github-ui/verified-fetch'

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

const mockIsFeatureEnabled = jest.mocked(isFeatureEnabled)

const mockVerifiedFetch = verifiedFetch as jest.Mock

jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))
describe('GiveFeedback', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders when not on mobile and lifecycle_label_name_updates is disabled', () => {
    mockIsFeatureEnabled.mockReturnValue(false)

    const {container} = render(<GiveFeedback />)

    expect(within(container).queryByText('Thoughts on GitHub Models?')).not.toBeInTheDocument()
    expect(within(container).queryByText('Preview')).not.toBeInTheDocument()
    expect(within(container).getByText('Beta')).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', feedbackUrl)
  })

  test('renders when on mobile and lifecycle_label_name_updates is disabled', () => {
    mockIsFeatureEnabled.mockReturnValue(false)

    const {container} = render(<GiveFeedback mobile />)

    expect(within(container).getByText('Thoughts on GitHub Models?')).toBeInTheDocument()
    expect(within(container).queryByText('Preview')).not.toBeInTheDocument()
    expect(within(container).getByText('Beta')).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', feedbackUrl)
  })

  test('renders when not on mobile and lifecycle_label_name_updates is enabled', () => {
    mockIsFeatureEnabled.mockImplementation(flag => flag === 'lifecycle_label_name_updates')

    const {container} = render(<GiveFeedback />)

    expect(within(container).queryByText('Thoughts on GitHub Models?')).not.toBeInTheDocument()
    expect(within(container).getByText('Preview')).toBeInTheDocument()
    expect(within(container).queryByText('Beta')).not.toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', feedbackUrl)
  })

  test('renders when on mobile and lifecycle_label_name_updates is enabled', () => {
    mockIsFeatureEnabled.mockImplementation(flag => flag === 'lifecycle_label_name_updates')

    const {container} = render(<GiveFeedback mobile />)

    expect(within(container).getByText('Thoughts on GitHub Models?')).toBeInTheDocument()
    expect(within(container).getByText('Preview')).toBeInTheDocument()
    expect(within(container).queryByText('Beta')).not.toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Give feedback'})).toHaveAttribute('href', feedbackUrl)
  })

  test('does not render a popover when not on playground', () => {
    const {container} = render(<GiveFeedback />, {
      appPayload: {
        enabled_features: {
          github_models_feedback_banner: false,
        },
      },
    })

    expect(within(container).queryByRole('button', {name: 'Give feedback'})).not.toBeInTheDocument()
    expect(within(container).queryByText('Welcome to GitHub Models!')).not.toBeInTheDocument()
    expect(within(container).queryByText('share feedback via discussion')).not.toBeInTheDocument()
    expect(within(container).queryByText('Book a call')).not.toBeInTheDocument()
  })

  test('does not render a popover when not on playground on mobile', () => {
    const {container} = render(<GiveFeedback mobile />, {
      appPayload: {
        enabled_features: {
          github_models_feedback_banner: false,
        },
      },
    })

    expect(within(container).queryByRole('button', {name: 'Give feedback'})).not.toBeInTheDocument()
    expect(within(container).queryByText('Welcome to GitHub Models!')).not.toBeInTheDocument()
    expect(within(container).queryByText('share feedback via discussion')).not.toBeInTheDocument()
    expect(within(container).queryByText('Book a call')).not.toBeInTheDocument()
  })

  test('does not render a popover when the feedback banner is enabled', () => {
    const {container} = render(<GiveFeedback playground />, {
      appPayload: {
        enabled_features: {
          github_models_feedback_banner: true,
        },
      },
    })

    expect(within(container).queryByRole('button', {name: 'Give feedback'})).not.toBeInTheDocument()
    expect(within(container).queryByText('Welcome to GitHub Models!')).not.toBeInTheDocument()
    expect(within(container).queryByText('share feedback via discussion')).not.toBeInTheDocument()
    expect(within(container).queryByText('Book a call')).not.toBeInTheDocument()
  })

  test('does not render a popover when on mobile and the feedback banner is enabled', () => {
    const {container} = render(<GiveFeedback playground mobile />, {
      appPayload: {
        enabled_features: {
          github_models_feedback_banner: true,
        },
      },
    })

    expect(within(container).queryByRole('button', {name: 'Give feedback'})).not.toBeInTheDocument()
    expect(within(container).queryByText('Welcome to GitHub Models!')).not.toBeInTheDocument()
    expect(within(container).queryByText('share feedback via discussion')).not.toBeInTheDocument()
    expect(within(container).queryByText('Book a call')).not.toBeInTheDocument()
  })

  test('renders a popover on land when on playground and the feedback banner is not enabled', () => {
    const {container} = render(<GiveFeedback playground />, {
      appPayload: {
        enabled_features: {
          github_models_feedback_banner: false,
        },
      },
      routePayload: {...mockShowModelPayload(), playgroundFeedbackPopoverDismissed: false},
    })

    expect(within(container).getByText('Welcome to GitHub Models!')).toBeInTheDocument()
    expect(within(container).getByText('share feedback via discussion')).toBeInTheDocument()
    expect(within(container).getByText('Book a call')).toBeInTheDocument()
  })

  test('renders a popover on land when on playground on mobile and the feedback banner is not enabled', () => {
    const {container} = render(<GiveFeedback playground mobile />, {
      appPayload: {
        enabled_features: {
          github_models_feedback_banner: false,
        },
      },
      routePayload: {...mockShowModelPayload(), playgroundFeedbackPopoverDismissed: false},
    })

    expect(within(container).getByText('Welcome to GitHub Models!')).toBeInTheDocument()
    expect(within(container).getByText('share feedback via discussion')).toBeInTheDocument()
    expect(within(container).getByText('Book a call')).toBeInTheDocument()
  })

  test('renders a popover only when the user clicks the give feedback button if the user already dismissed the notice', async () => {
    const {user, container} = render(<GiveFeedback playground />, {
      appPayload: {
        enabled_features: {
          github_models_feedback_banner: false,
        },
      },
      routePayload: {...mockShowModelPayload(), playgroundFeedbackPopoverDismissed: true},
    })

    expect(within(container).queryByText('Welcome to GitHub Models!')).not.toBeInTheDocument()
    expect(within(container).queryByText('share feedback via discussion')).not.toBeInTheDocument()
    expect(within(container).queryByText('Book a call')).not.toBeInTheDocument()

    const button = within(container).getByRole('button', {name: 'Give feedback'})
    await user.click(button)

    expect(within(container).getByText('Welcome to GitHub Models!')).toBeInTheDocument()
    expect(within(container).getByText('share feedback via discussion')).toBeInTheDocument()
    expect(within(container).getByText('Book a call')).toBeInTheDocument()
  })

  test('renders a popover only when the user clicks the give feedback button if the user already dismissed the notice and when on mobile', async () => {
    const {user, container} = render(<GiveFeedback playground mobile />, {
      appPayload: {
        enabled_features: {
          github_models_feedback_banner: false,
        },
      },
      routePayload: {...mockShowModelPayload(), playgroundFeedbackPopoverDismissed: true},
    })

    expect(within(container).queryByText('Welcome to GitHub Models!')).not.toBeInTheDocument()
    expect(within(container).queryByText('share feedback via discussion')).not.toBeInTheDocument()
    expect(within(container).queryByText('Book a call')).not.toBeInTheDocument()

    const button = within(container).getByRole('button', {name: 'Give feedback'})
    await user.click(button)

    expect(within(container).getByText('Welcome to GitHub Models!')).toBeInTheDocument()
    expect(within(container).getByText('share feedback via discussion')).toBeInTheDocument()
    expect(within(container).getByText('Book a call')).toBeInTheDocument()
  })

  test('dismisses the notice if the user clicks the x button', async () => {
    const {user, container} = render(<GiveFeedback playground mobile />, {
      appPayload: {
        enabled_features: {
          github_models_feedback_banner: false,
        },
      },
      routePayload: {...mockShowModelPayload(), playgroundFeedbackPopoverDismissed: false},
    })

    expect(within(container).getByText('Welcome to GitHub Models!')).toBeInTheDocument()
    expect(within(container).getByText('share feedback via discussion')).toBeInTheDocument()
    expect(within(container).getByText('Book a call')).toBeInTheDocument()

    const closeButton = within(container).getByRole('button', {name: 'Close'})
    await user.click(closeButton)

    expect(mockVerifiedFetch).toHaveBeenCalledWith(
      `/settings/dismiss-notice/github_models_playground_feedback_popover`,
      {
        method: 'POST',
      },
    )
  })
})
