import {screen, waitFor, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {modelFeedbackPath} from '@github-ui/paths'
import {PlaygroundChatMessage} from '../PlaygroundChatMessage'
import {mockModelState, mockStoredMessage} from './mocks'
import {mockModel} from '../../__tests__/mocks'
import {Feedback} from '../GettingStartedDialog/types'
import {mockShowModelPayload} from '../../../show/components/__tests__/mocks'
import type {ImageInputs} from '../../../../types'
import {PlaygroundChatSuggestion, TokenLimitReachedResponseErrorDescription} from '../../../../utils/playground-types'
import {Panel} from '../../../../utils/playground-manager'
import {sendEvent} from '@github-ui/hydro-analytics'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args)}
})

const mockSetSearchParams = jest.fn()
const mockUseSearchParams = [new URLSearchParams(''), mockSetSearchParams]
jest.mock('@github-ui/use-navigate', () => {
  return {
    useSearchParams: () => mockUseSearchParams,
  }
})

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: jest.fn(),
  }
})

describe('PlaygroundChatMessage', () => {
  const handleRegenerate = jest.fn().mockName('handleRegenerate')
  const handleEdit = jest.fn().mockName('handleEdit')
  const handleClearHistory = jest.fn().mockName('handleClearHistory')
  const handleImproveSuggestion = jest.fn().mockName('handleImproveSuggestion')

  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders a user message', () => {
    const messageBody = 'I prefer the taste of Diet Pepsi.'
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
    )

    const messageEl = within(container).getByTestId('playground-chat-message')
    expect(messageEl).toBeInTheDocument()
    expect(within(container).getByRole('paragraph')).toHaveTextContent(messageBody)
    expect(screen.queryByRole('button', {name: 'Positive'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Negative'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Copy to clipboard'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Regenerate'})).not.toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Provide feedback'})).not.toBeInTheDocument()
    expect(screen.queryByTestId('playground-error')).not.toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Reset chat'})).not.toBeInTheDocument()
    expect(handleRegenerate).not.toHaveBeenCalled()
    expect(handleClearHistory).not.toHaveBeenCalled()
  })

  test('renders an assistant message', () => {
    const modelName = 'SomeConvenientModel'
    const model = Object.assign({}, mockModel, {friendly_name: modelName})
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
    expect(within(container).getByRole('paragraph')).toHaveTextContent(messageBody)
    expect(within(container).getByRole('button', {name: 'Positive'})).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Negative'})).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Regenerate'})).not.toBeInTheDocument()
    expect(screen.queryByRole('dialog', {name: 'Provide feedback'})).not.toBeInTheDocument()
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

    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(modelFeedbackPath(mockModel), {
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

    expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(modelFeedbackPath(mockModel), {
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

  test('allows editing the last message', async () => {
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
        handleEdit={handleEdit}
      />,
      {routePayload},
    )

    const editButtonMenu = within(container).getByRole('button', {name: 'Edit prompt menu'})
    expect(editButtonMenu).toBeInTheDocument()
    expect(editButtonMenu).toBeEnabled()

    await user.click(editButtonMenu)

    const editButton = screen.getByRole('menuitem', {name: 'Edit prompt'})

    await user.click(editButton)

    expect(handleEdit).toHaveBeenCalled()
  })

  test('allows selecting an improvement suggestion', async () => {
    const modelState = mockModelState({catalogData: mockModel})
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant'})

    const routePayload = mockShowModelPayload({model: mockModel, improvedPromptModel: mockModel})

    const {container, user} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={Panel.Main}
        message={message}
        lastIndex
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
        handleEdit={handleEdit}
        handleImproveSuggestion={handleImproveSuggestion}
      />,
      {routePayload},
    )

    const editButtonMenu = within(container).getByRole('button', {name: 'Edit prompt menu'})
    expect(editButtonMenu).toBeInTheDocument()
    expect(editButtonMenu).toBeEnabled()

    await user.click(editButtonMenu)

    expect(screen.getByTestId('playground-chat-message-improvement-suggestions')).toBeInTheDocument()
    const option = screen.getByRole('menuitem', {name: 'Cite sources in response'})

    await user.click(option)

    expect(sendEvent).toHaveBeenCalledWith(`${PlaygroundChatSuggestion}.cite_sources.clicked`)
    expect(handleImproveSuggestion).toHaveBeenCalledWith(Panel.Main, 'Cite the sources in the response.')
  })

  test('does not render suggestions when handleImproveSuggestion is not passed as props', async () => {
    const modelState = mockModelState({catalogData: mockModel})
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant'})

    const routePayload = mockShowModelPayload({model: mockModel, improvedPromptModel: mockModel})

    const {container, user} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={Panel.Main}
        message={message}
        lastIndex
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
        handleEdit={handleEdit}
      />,
      {routePayload},
    )

    const editButtonMenu = within(container).getByRole('button', {name: 'Edit prompt menu'})
    expect(editButtonMenu).toBeInTheDocument()
    expect(editButtonMenu).toBeEnabled()

    await user.click(editButtonMenu)

    expect(screen.queryByTestId('playground-chat-message-improvement-suggestions')).not.toBeInTheDocument()
    expect(screen.queryByRole('menuitem', {name: 'Cite sources in response'})).not.toBeInTheDocument()
  })

  test('does not suggest different models when the model has low rate limit tier', async () => {
    const clonedModel = {...mockModel, rate_limit_tier: 'low'}
    const modelState = mockModelState({catalogData: clonedModel})
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant'})

    const routePayload = mockShowModelPayload({model: mockModel, improvedPromptModel: mockModel})

    const {container, user} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={Panel.Main}
        message={message}
        lastIndex
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
        handleEdit={handleEdit}
        lowRateLimitTierModels={[mockModel]}
        handleImproveSuggestion={handleImproveSuggestion}
      />,
      {routePayload},
    )

    const editButtonMenu = within(container).getByRole('button', {name: 'Edit prompt menu'})
    expect(editButtonMenu).toBeInTheDocument()
    expect(editButtonMenu).toBeEnabled()

    await user.click(editButtonMenu)

    expect(screen.queryByText(mockModel.friendly_name)).not.toBeInTheDocument()
  })

  test('suggests different models', async () => {
    const modelState = mockModelState({catalogData: mockModel})
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant'})

    const routePayload = mockShowModelPayload({model: mockModel, improvedPromptModel: mockModel})

    const lowRateLimitTierModel = {...mockModel, friendly_name: 'lowRateLimitTierModel', rate_limit_tier: 'low'}
    const {container, user} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={Panel.Main}
        message={message}
        lastIndex
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
        handleEdit={handleEdit}
        handleImproveSuggestion={handleImproveSuggestion}
        lowRateLimitTierModels={[lowRateLimitTierModel]}
      />,
      {routePayload},
    )

    const editButtonMenu = within(container).getByRole('button', {name: 'Edit prompt menu'})
    expect(editButtonMenu).toBeInTheDocument()
    expect(editButtonMenu).toBeEnabled()

    await user.click(editButtonMenu)

    const item = screen.getByRole('menuitem', {name: 'Make response cheaper'})
    await user.click(item)

    expect(screen.getByText(lowRateLimitTierModel.friendly_name)).toBeInTheDocument()
  })

  test('suggests only OpenAI family models when the user is on an OpenIA model and clicks the make response faster option', async () => {
    const modelState = mockModelState({catalogData: mockModel})
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant'})

    const routePayload = mockShowModelPayload({model: mockModel, improvedPromptModel: mockModel})

    const openAIModel = {...mockModel, friendly_name: 'openAI model', rate_limit_tier: 'low'}
    const nonOpenAIModel = {
      ...mockModel,
      publisher: 'random',
      friendly_name: 'non openAI model',
      rate_limit_tier: 'low',
    }

    const {container, user} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={Panel.Main}
        message={message}
        lastIndex
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
        handleEdit={handleEdit}
        handleImproveSuggestion={handleImproveSuggestion}
        lowRateLimitTierModels={[openAIModel, nonOpenAIModel]}
      />,
      {routePayload},
    )

    const editButtonMenu = within(container).getByRole('button', {name: 'Edit prompt menu'})
    expect(editButtonMenu).toBeInTheDocument()
    expect(editButtonMenu).toBeEnabled()

    await user.click(editButtonMenu)

    const item = screen.getByRole('menuitem', {name: 'Make response faster'})
    await user.click(item)

    expect(screen.getByText(openAIModel.friendly_name)).toBeInTheDocument()
    expect(screen.queryByText(nonOpenAIModel.friendly_name)).not.toBeInTheDocument()
  })

  test('adds the suggestion query string when a suggested model is clicked', async () => {
    const modelState = mockModelState({catalogData: mockModel})
    const message = Object.assign({}, mockStoredMessage, {role: 'assistant'})

    const routePayload = mockShowModelPayload({model: mockModel, improvedPromptModel: mockModel})
    const spy = jest.spyOn(URLSearchParams.prototype, 'set')

    const lowRateLimitTierModel = {...mockModel, friendly_name: 'lowRateLimitTierModel', rate_limit_tier: 'low'}
    const {container, user} = render(
      <PlaygroundChatMessage
        isLoading={false}
        isError={false}
        index={Panel.Main}
        message={message}
        lastIndex
        model={modelState}
        handleClearHistory={handleClearHistory}
        handleRegenerate={handleRegenerate}
        handleEdit={handleEdit}
        handleImproveSuggestion={handleImproveSuggestion}
        lowRateLimitTierModels={[lowRateLimitTierModel]}
      />,
      {routePayload},
    )

    const editButtonMenu = within(container).getByRole('button', {name: 'Edit prompt menu'})
    expect(editButtonMenu).toBeInTheDocument()
    expect(editButtonMenu).toBeEnabled()

    await user.click(editButtonMenu)

    const item = screen.getByRole('menuitem', {name: 'Make response cheaper'})
    await user.click(item)

    const suggestedModel = screen.getByText(lowRateLimitTierModel.friendly_name)
    await user.click(suggestedModel)

    expect(spy).toHaveBeenCalledWith('compare_to', mockModel.name)
    expect(spy).toHaveBeenCalledWith('resend-user-prompt', 'true')
    expect(mockSetSearchParams).toHaveBeenCalledTimes(1)
    expect(sendEvent).toHaveBeenCalledWith(`${PlaygroundChatSuggestion}.make_response_cheaper.clicked`)
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
    expect(screen.queryByRole('button', {name: 'Positive'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Negative'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Copy to clipboard'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Regenerate'})).not.toBeInTheDocument()

    // There will always be two buttons rendered in the Banner HTML, depending on viewport size, only one will be visible each time
    const resetChatButton = within(container).getAllByRole('button', {
      name: 'Reset chat',
    })[0] as HTMLButtonElement
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
    expect(screen.queryByRole('button', {name: 'Positive'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Negative'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Copy to clipboard'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Regenerate'})).not.toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Reset chat'})).not.toBeInTheDocument()
    expect(handleClearHistory).not.toHaveBeenCalled()
    expect(handleRegenerate).not.toHaveBeenCalled()
  })
})
