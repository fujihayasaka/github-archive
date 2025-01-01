import {GiveFeedbackPopover} from '../GiveFeedbackPopover'
import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {sendStats} from '@github-ui/stats'
import {bookACallUrl, feedbackUrl} from '../../constants'

jest.mock('@github-ui/stats', () => ({
  sendStats: jest.fn().mockName('sendStats'),
}))

const handleClose = jest.fn().mockName('handleClose')

describe('GiveFeedbackPopover', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders the popover view', async () => {
    render(<GiveFeedbackPopover handleClose={handleClose} />)
    expect(screen.getByText('Welcome to GitHub Models!')).toBeInTheDocument()
    expect(screen.getByText('share feedback via discussion')).toBeInTheDocument()
    expect(screen.getByRole('link', {name: 'Book a call'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(sendStats).toHaveBeenCalledWith({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_POPOVER_DISPLAYED',
    })
  })

  test('takes the user to the discussion page when the share feedback link is clicked', async () => {
    const {user} = render(<GiveFeedbackPopover handleClose={handleClose} />)

    const link = screen.getByText('share feedback via discussion')
    await user.click(link)
    expect(link.getAttribute('href')).toBe(feedbackUrl)
    expect(sendStats).toHaveBeenCalledWith({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_POPOVER_SHARE_FEEDBACK_SELECTED',
    })
  })

  test('takes the user to the calendar page to book a call when book a call is clicked', async () => {
    const {user} = render(<GiveFeedbackPopover handleClose={handleClose} />)
    const bookACallLink = screen.getByRole('link', {name: 'Book a call'})
    await user.click(bookACallLink)
    expect(bookACallLink.getAttribute('href')).toBe(bookACallUrl)
    expect(sendStats).toHaveBeenCalledWith({
      incrementKey: 'MODELS_PLAYGROUND_FEEDBACK_POPOVER_BOOK_CALL_SELECTED',
    })
  })
})
