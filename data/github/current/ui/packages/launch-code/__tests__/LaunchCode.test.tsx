import {announceFromElement} from '@github-ui/aria-live'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {screen, waitFor} from '@testing-library/react'
import {LaunchCode} from '../LaunchCode'
import {handleSubmit} from '../helpers/handle-submit'
import {getLaunchCodeProps} from '../test-utils/mock-data'

const mockVerifiedFetch = verifiedFetch as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))
jest.mock('../helpers/handle-submit', () => ({
  handleSubmit: jest.fn(),
}))
const sendAnalyticsEvent = jest.fn().mockName('sendAnalyticsEvent')
jest.mock('@github-ui/use-analytics', () => ({
  useAnalytics: () => ({sendAnalyticsEvent}),
}))
jest.mock('@github-ui/aria-live', () => ({
  announceFromElement: jest.fn(),
}))

beforeEach(() => {
  jest.resetAllMocks()
})
afterEach(() => {
  jest.restoreAllMocks()
})

const setup = () => {
  const props = getLaunchCodeProps()
  render(<LaunchCode {...props} />)
}

describe('Form submittal', () => {
  it('automatically submits the form when 8 numbers are pasted into the inputs', async () => {
    setup()

    const inputField = screen.getByTestId('launch-code-0')
    const userEvent = setupUserEvent()
    // Click into the first input field
    await userEvent.click(inputField)
    // Simulate pasting an 8-digit code
    await userEvent.paste('12345678')

    expect(handleSubmit).toHaveBeenCalledTimes(1)
  })

  it('automatically submits the form when 8 numbers are typed into the inputs', async () => {
    setup()

    const inputField = screen.getByTestId('launch-code-0')
    const userEvent = setupUserEvent()
    // Simulate typing an 8 digit code
    await userEvent.type(inputField, '12345678')

    expect(handleSubmit).toHaveBeenCalledTimes(1)
  })

  it('does not automatically submit the form if less than 8 numbers are pasted into the inputs', async () => {
    setup()

    const inputField = screen.getByTestId('launch-code-0')
    const userEvent = setupUserEvent()
    // Click into the first input field
    await userEvent.click(inputField)
    // Simulate pasting a 4-digit code
    await userEvent.paste('1234')

    expect(handleSubmit).toHaveBeenCalledTimes(0)
  })

  it('does not automatically submit the form if less than 8 numbers are typed into the inputs', async () => {
    setup()

    const inputField = screen.getByTestId('launch-code-0')
    const userEvent = setupUserEvent()
    // Simulate typing 4 digits
    await userEvent.type(inputField, '1234')

    expect(handleSubmit).toHaveBeenCalledTimes(0)
  })

  it('does not submit the form when Continue button is pressed, if no inputs are filled', async () => {
    setup()

    const userEvent = setupUserEvent()
    const button = screen.getByRole('button', {name: 'Continue'})
    await userEvent.click(button)

    expect(handleSubmit).toHaveBeenCalledTimes(0)
  })

  it('does not submit the form when Continue button is pressed, if any inputs are empty', async () => {
    setup()

    const inputField = screen.getByTestId('launch-code-0')
    const userEvent = setupUserEvent()
    // Simulate typing 6 digits
    await userEvent.type(inputField, '123456')
    const button = screen.getByRole('button', {name: 'Continue'})
    await userEvent.click(button)

    expect(handleSubmit).toHaveBeenCalledTimes(0)
  })

  it('does not accept letters or special characters, only numbers', async () => {
    setup()

    const inputField = screen.getByTestId('launch-code-0')
    const userEvent = setupUserEvent()

    // Simulate typing some numbers, some unaccepted characters
    await userEvent.type(inputField, 'a12!b3')
    expect(screen.queryByDisplayValue('a')).not.toBeInTheDocument()
    expect(screen.getByDisplayValue(1)).toBeInTheDocument()
    expect(screen.getByDisplayValue(2)).toBeInTheDocument()
    expect(screen.queryByDisplayValue('!')).not.toBeInTheDocument()
    expect(screen.queryByDisplayValue('b')).not.toBeInTheDocument()
    expect(screen.getByDisplayValue(3)).toBeInTheDocument()
    expect(handleSubmit).toHaveBeenCalledTimes(0)
  })
})

describe('Resend launch code', () => {
  it('Resends the launch code and displays a success message', async () => {
    setup()
    mockVerifiedFetch.mockResolvedValue({
      status: 200,
    })

    const userEvent = setupUserEvent()
    const button = screen.getByRole('button', {name: 'Resend the code'})
    await userEvent.click(button)

    const resentText = screen.getByText('Email was resent')
    expect(resentText).toBeInTheDocument()
    expect(announceFromElement).toHaveBeenCalledTimes(1)
    expect(announceFromElement).toHaveBeenCalledWith(resentText)
  })

  it('Logs an error if resend fails', async () => {
    setup()
    mockVerifiedFetch.mockResolvedValue({
      status: 500,
    })
    const userEvent = setupUserEvent()
    const button = screen.getByRole('button', {name: 'Resend the code'})
    await userEvent.click(button)

    expect(sendAnalyticsEvent).toHaveBeenCalled()
    await waitFor(() => expect(screen.queryByTestId('resend-email-success-message')).not.toBeInTheDocument())
  })
})
