import {screen, waitFor, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import type {UserHookPayload} from '@github-ui/use-user'
import {PlaygroundChatMessage} from '../PlaygroundChatMessage'
import {mockModelState, mockStoredMessage} from './mocks'
import {mockModel} from '../../__tests__/mocks'
import {ModelUrlHelper} from '../../../../utils/model-url-helper'
import {Feedback} from '../GettingStartedDialog/types'
import {mockShowModelPayload} from '../../../show/components/__tests__/mocks'
import type {ImageInputs} from '../../../../types'
import {TokenLimitReachedResponseErrorDescription} from '../../../../utils/playground-types'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

jest.mock('@github-ui/verified-fetch', () => {
  return {verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args)}
})

describe('PlaygroundChatMessage', () => {
  const handleRegenerate = jest.fn().mockName('handleRegenerate')
  const handleClearHistory = jest.fn().mockName('handleClearHistory')

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders a user message', () => {
    const currentUserName = 'Yuexin User'
    const messageBody = 'I prefer the taste of Diet Pepsi.'
    const currentUser: Partial<UserHookPayload['current_user']> = {name: currentUserName}
    const modelState = mockModelState()
    const message = Object.assign({}, mockStoredMessage, {message: messageBody, role: 'user'})

    const {container} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={0}
        message={message}
        lastIndex={false}
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
      />,
      {appPayload: {current_user: currentUser}},
    )

    const messageEl = within(container).getByTestId('playground-chat-message')
    expect(messageEl).toBeInTheDocument()
    expect(within(messageEl).getByTestId('github-avatar')).toBeInTheDocument()
    expect(screen.queryByTestId('models-avatar')).not.toBeInTheDocument()
    expect(within(messageEl).getByTestId('chat-message-author-name')).toHaveTextContent(currentUserName)
    expect(within(messageEl).getByTestId('message-timestamp')).toBeInTheDocument()
    expect(within(container).getByRole('paragraph')).toHaveTextContent(messageBody)
    expect(screen.queryByRole('button', {name: 'Positive'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Negative'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Copy to clipboard'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Regenerate'})).not.toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Provide feedback'})).not.toBeInTheDocument()
    expect(screen.queryByText('Responding...')).not.toBeInTheDocument()
    expect(screen.queryByTestId('playground-error')).not.toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Reset chat'})).not.toBeInTheDocument()
    expect(handleRegenerate).not.toHaveBeenCalled()
    expect(handleClearHistory).not.toHaveBeenCalled()
  })

  test('renders an assistant message', () => {
    const modelName = 'SomeConvenientModel'
    const model = Object.assign({}, mockModel, {name: modelName})
    const modelState = mockModelState({catalogData: model})
    const messageBody = 'Who can forget about Diet Coke, though?'
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant', message: messageBody})

    const {container} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={0}
        message={message}
        lastIndex={false}
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
      />,
    )

    const messageEl = within(container).getByTestId('playground-chat-message')
    expect(messageEl).toBeInTheDocument()
    expect(within(messageEl).getByTestId('models-avatar')).toBeInTheDocument()
    expect(within(messageEl).getByTestId('message-timestamp')).toBeInTheDocument()
    expect(screen.queryByTestId('github-avatar')).not.toBeInTheDocument()
    expect(within(messageEl).getByTestId('chat-message-author-name')).toHaveTextContent(modelName)
    expect(within(container).getByRole('paragraph')).toHaveTextContent(messageBody)
    expect(within(container).getByRole('button', {name: 'Positive'})).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Negative'})).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Regenerate'})).not.toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Provide feedback'})).not.toBeInTheDocument()
    expect(screen.queryByText('Responding...')).not.toBeInTheDocument()
    expect(screen.queryByTestId('playground-error')).not.toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Reset chat'})).not.toBeInTheDocument()
    expect(handleRegenerate).not.toHaveBeenCalled()
    expect(handleClearHistory).not.toHaveBeenCalled()
  })

  test('allows regenerating the last message from the assistant', async () => {
    const modelState = mockModelState()
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant'})
    const index = 0

    const {container, user} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={index}
        message={message}
        lastIndex
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
      />,
    )

    expect(within(container).getByTestId('playground-chat-message')).toBeInTheDocument()
    const regenerateButton = within(container).getByRole('button', {name: 'Regenerate'})
    expect(regenerateButton).toBeInTheDocument()
    expect(handleRegenerate).not.toHaveBeenCalled()

    await user.click(regenerateButton)

    expect(handleRegenerate).toHaveBeenCalledTimes(1)
    expect(handleRegenerate).toHaveBeenCalledWith(index)
    expect(handleClearHistory).not.toHaveBeenCalled()
  })

  test('does not show Regenerate button for last user message', () => {
    const modelState = mockModelState()
    const message = Object.assign({}, mockStoredMessage, {role: 'user'})

    const {container} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={0}
        message={message}
        lastIndex
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
      />,
    )

    expect(within(container).getByTestId('playground-chat-message')).toBeInTheDocument()
    expect(handleRegenerate).not.toHaveBeenCalled()
    expect(screen.queryByRole('button', {name: 'Regenerate'})).not.toBeInTheDocument()
    expect(handleClearHistory).not.toHaveBeenCalled()
  })

  test('allows submitting positive feedback on last assistant message', async () => {
    const modelState = mockModelState({catalogData: mockModel})
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant'})
    mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => {}})

    const {container, user} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={0}
        message={message}
        lastIndex
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
      />,
    )

    const positiveFeedbackButton = within(container).getByRole('button', {name: 'Positive'})
    expect(positiveFeedbackButton).toBeInTheDocument()
    expect(positiveFeedbackButton).toBeEnabled()
    expect(within(container).getByRole('button', {name: 'Negative'})).toBeInTheDocument()

    await user.click(positiveFeedbackButton)

    expect(screen.queryByRole('dialog', {name: 'Provide feedback'})).not.toBeInTheDocument()

    await waitFor(() => {
      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    })

    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(ModelUrlHelper.feedbackUrl(mockModel), {
      body: {
        feedback: {
          contactConsent: false,
          feedbackText: '',
          model: mockModel.name,
          reasons: [],
          satisfaction: Feedback.POSITIVE,
        },
      },
      method: 'POST',
    })
    expect(within(container).getByRole('button', {name: 'Positive'})).toBeDisabled()
    expect(within(container).queryByRole('button', {name: 'Negative'})).not.toBeInTheDocument()
    expect(handleClearHistory).not.toHaveBeenCalled()
  })

  test('allows submitting negative feedback on last assistant message', async () => {
    const modelState = mockModelState({catalogData: mockModel})
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant'})
    mockVerifiedFetchJSON.mockResolvedValue({status: 200, ok: true, json: async () => {}})
    const routePayload = mockShowModelPayload({model: mockModel})

    const {container, user} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={0}
        message={message}
        lastIndex
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
      />,
      {routePayload},
    )

    const negativeFeedbackButton = within(container).getByRole('button', {name: 'Negative'})
    expect(negativeFeedbackButton).toBeInTheDocument()
    expect(negativeFeedbackButton).toBeEnabled()
    expect(within(container).getByRole('button', {name: 'Positive'})).toBeInTheDocument()

    await user.click(negativeFeedbackButton)

    expect(mockVerifiedFetchJSON).not.toHaveBeenCalled()
    const dialog = screen.getByRole('dialog', {name: 'Provide feedback'})
    expect(dialog).toBeInTheDocument()
    expect(within(dialog).getByRole('button', {name: 'Close'})).toBeInTheDocument()
    const submitButton = within(dialog).getByRole('button', {name: 'Submit feedback'})
    expect(submitButton).toBeInTheDocument()
    const checkbox = within(dialog).getByRole('checkbox', {name: 'Not true'})
    expect(checkbox).toBeInTheDocument()

    await user.click(checkbox)
    await user.click(submitButton)

    expect(screen.queryByRole('dialog', {name: 'Provide feedback'})).not.toBeInTheDocument()

    await waitFor(() => {
      expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
    })

    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(ModelUrlHelper.feedbackUrl(mockModel), {
      body: {
        feedback: {
          contactConsent: false,
          feedbackText: '',
          model: mockModel.name,
          reasons: ['not true'],
          satisfaction: Feedback.NEGATIVE,
        },
      },
      method: 'POST',
    })
    expect(within(container).getByRole('button', {name: 'Negative'})).toBeDisabled()
    expect(within(container).queryByRole('button', {name: 'Positive'})).not.toBeInTheDocument()
    expect(handleClearHistory).not.toHaveBeenCalled()
  })

  test('renders loading state for assistant message', () => {
    const modelState = mockModelState({catalogData: mockModel})
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant'})
    const routePayload = mockShowModelPayload({model: mockModel})

    const {container} = render(
      <PlaygroundChatMessage
        isLoading
        isError={false}
        index={0}
        message={message}
        lastIndex
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
      />,
      {routePayload},
    )

    const messageEl = within(container).getByTestId('playground-chat-message')
    expect(messageEl).toBeInTheDocument()
    expect(within(messageEl).getByText('Responding...')).toBeInTheDocument()
    expect(screen.queryByTestId('message-timestamp')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Positive'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Negative'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Copy to clipboard'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Regenerate'})).not.toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Provide feedback'})).not.toBeInTheDocument()
    expect(handleClearHistory).not.toHaveBeenCalled()
  })

  test('renders for image message', () => {
    const modelState = mockModelState()
    const imageUrl1 = 'https://example.com/image1.jpg'
    const imageUrl2 = 'https://github.com/octocat.png'
    const imgMsg1: ImageInputs = {type: 'image_url', image_url: {url: imageUrl1}}
    const imgMsg2: ImageInputs = {type: 'image_url', image_url: {url: imageUrl2}}
    const message = Object.assign({}, mockStoredMessage, {message: [imgMsg1, imgMsg2]})

    const {container} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={0}
        message={message}
        lastIndex={false}
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
      />,
    )

    const images = within(container).getAllByRole('img', {name: 'Attachment'})
    expect(images).toHaveLength(2)
    expect(images[0]).toHaveAttribute('src', imageUrl1)
    expect(images[1]).toHaveAttribute('src', imageUrl2)
  })

  test('renders a token limit error', async () => {
    const modelState = mockModelState()
    const message = Object.assign({}, mockStoredMessage, {
      message: TokenLimitReachedResponseErrorDescription,
      role: 'error',
    })

    const {container, user} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError
        index={0}
        message={message}
        lastIndex={false}
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
      />,
    )

    expect(within(container).getByTestId('playground-error')).toBeInTheDocument()
    const messageEl = within(container).getByTestId('playground-chat-message')
    expect(messageEl).toBeInTheDocument()
    expect(within(messageEl).getByTestId('models-avatar')).toBeInTheDocument()
    expect(screen.queryByTestId('github-avatar')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Positive'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Negative'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Copy to clipboard'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Regenerate'})).not.toBeInTheDocument()
    const resetChatButton = within(container).getByRole('button', {name: 'Reset chat'})
    expect(resetChatButton).toBeInTheDocument()
    expect(handleClearHistory).not.toHaveBeenCalled()

    await user.click(resetChatButton)

    expect(handleClearHistory).toHaveBeenCalledTimes(1)
    expect(handleRegenerate).not.toHaveBeenCalled()
  })

  test('renders a general error', () => {
    const modelState = mockModelState()
    const message = Object.assign({}, mockStoredMessage, {message: 'o noes', role: 'error'})

    const {container} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError
        index={0}
        message={message}
        lastIndex={false}
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
      />,
    )

    expect(within(container).getByTestId('playground-error')).toBeInTheDocument()
    const messageEl = within(container).getByTestId('playground-chat-message')
    expect(messageEl).toBeInTheDocument()
    expect(within(messageEl).getByTestId('models-avatar')).toBeInTheDocument()
    expect(screen.queryByTestId('github-avatar')).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Positive'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Negative'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Copy to clipboard'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Regenerate'})).not.toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Reset chat'})).not.toBeInTheDocument()
    expect(handleClearHistory).not.toHaveBeenCalled()
    expect(handleRegenerate).not.toHaveBeenCalled()
  })
})
