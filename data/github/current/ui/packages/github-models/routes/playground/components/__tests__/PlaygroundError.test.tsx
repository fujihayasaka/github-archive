import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {
  jsonFormatErrorMessage,
  jsonSchemaFormatErrorMessage,
  PlaygroundError,
  rateLimitDocsUrl,
  rateLimitedMessage,
} from '../PlaygroundError'

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

    // There will always be two buttons rendered in the Banner HTML, depending on viewport size, only one will be visible each time
    const resetChatButton = within(container).getAllByRole('button', {
      name: 'Reset chat',
    })[0] as HTMLButtonElement
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

  test('renders for a JSON format error', async () => {
    const {container} = render(
      <PlaygroundError
        message={jsonFormatErrorMessage}
        showResetButton={false}
        handleClearHistory={handleClearHistory}
      />,
    )

    const errorContainer = within(container).getByTestId('playground-error')
    expect(errorContainer).toBeInTheDocument()
    expect(within(errorContainer).queryByText(rateLimitedMessage)).not.toBeInTheDocument()
    expect(
      within(errorContainer).getByText(/Please adjust your input message or system prompt to include the word/),
    ).toBeInTheDocument()
  })

  test('renders for a JSON schema format error', () => {
    const {container} = render(
      <PlaygroundError
        message={jsonSchemaFormatErrorMessage}
        showResetButton={false}
        handleClearHistory={handleClearHistory}
      />,
    )

    const errorContainer = within(container).getByTestId('playground-error')
    expect(errorContainer).toBeInTheDocument()
    expect(within(errorContainer).getByText(/Please adjust your JSON schema to address/)).toBeInTheDocument()
    expect(
      within(errorContainer).getByText(/structuring your JSON schema correctly to generate outputs/),
    ).toBeInTheDocument()
  })
})
