import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PlaygroundError, rateLimitDocsUrl, rateLimitedMessage} from '../PlaygroundError'

describe('PlaygroundError', () => {
  const handleClearHistory = jest.fn().mockName('handleClearHistory')

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders with a custom error message', async () => {
    const message = 'Hello world, I am a sample error message.'

    const {container, user} = render(
      <PlaygroundError message={message} showResetButton handleClearHistory={handleClearHistory} />,
    )

    const errorContainer = within(container).getByTestId('playground-error')
    expect(errorContainer).toBeInTheDocument()
    expect(within(errorContainer).queryByText(rateLimitedMessage)).not.toBeInTheDocument()
    expect(within(errorContainer).getByText(message)).toBeInTheDocument()
    expect(within(errorContainer).queryByRole('link', {name: 'usage rate limits'})).not.toBeInTheDocument()
    const resetChatButton = within(errorContainer).getByRole('button', {name: 'Reset chat'})
    expect(resetChatButton).toBeInTheDocument()
    expect(handleClearHistory).not.toHaveBeenCalled()

    await user.click(resetChatButton)

    expect(handleClearHistory).toHaveBeenCalledTimes(1)
  })

  test('renders for a rate limit error', async () => {
    const {container} = render(
      <PlaygroundError message={rateLimitedMessage} showResetButton={false} handleClearHistory={handleClearHistory} />,
    )

    const errorContainer = within(container).getByTestId('playground-error')
    expect(errorContainer).toBeInTheDocument()
    expect(within(errorContainer).queryByText(rateLimitedMessage)).not.toBeInTheDocument()
    expect(within(errorContainer).getByRole('link', {name: 'usage rate limits'})).toHaveAttribute(
      'href',
      rateLimitDocsUrl,
    )
    expect(within(errorContainer).queryByRole('button', {name: 'Reset chat'})).not.toBeInTheDocument()
    expect(handleClearHistory).not.toHaveBeenCalled()
  })
})
