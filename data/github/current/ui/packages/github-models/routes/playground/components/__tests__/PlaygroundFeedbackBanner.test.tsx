import {screen} from '@testing-library/react'
import {PlaygroundFeedbackBanner} from '../PlaygroundFeedbackBanner'
import {render} from '@github-ui/react-core/test-utils'
import {sendStats} from '@github-ui/stats'
import {bookACallUrl, feedbackUrl} from '../../../../constants'

jest.mock('@github-ui/stats', () => ({
  sendStats: jest.fn().mockName('sendStats'),
}))

describe('PlaygroundFeedbackBanner', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders the feedback banner', () => {
    render(<PlaygroundFeedbackBanner />)

    expect(screen.getByText(/Got feedback/i)).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Book a call'})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'share feedback via discussion'})).toBeInTheDocument()
    expect(sendStats).toHaveBeenCalledWith({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_BANNER_DISPLAYED',
    })
  })

  test('takes the user to the calendar page to book a call when book a call is clicked', async () => {
    const {user} = render(<PlaygroundFeedbackBanner />)
    const bookACallButton = screen.getByRole('link', {name: 'Book a call'})
    await user.click(bookACallButton)
    expect(bookACallButton.getAttribute('href')).toBe(bookACallUrl)
    expect(sendStats).toHaveBeenCalledWith({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_BANNER_BOOK_CALL_SELECTED',
    })
  })

  test('takes the user to the discussion page when the share feedback link is clicked', async () => {
    const {user} = render(<PlaygroundFeedbackBanner />)
    const shareFeedbackButton = screen.getByRole('link', {name: 'share feedback via discussion'})
    await user.click(shareFeedbackButton)
    expect(shareFeedbackButton.getAttribute('href')).toBe(feedbackUrl)
    expect(sendStats).toHaveBeenCalledWith({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_BANNER_SHARE_FEEDBACK_SELECTED',
    })
  })
})
