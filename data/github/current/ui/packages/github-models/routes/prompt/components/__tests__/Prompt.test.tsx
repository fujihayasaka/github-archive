import {AzureModelClient} from '../../../../utils/azure-model-client'
import {PromptEvalsStateProvider} from '../../contexts/PromptEvalsStateContext'
import type {UserHookPayload} from '@github-ui/use-user'
import {Prompt} from '../Prompt'
import {render} from '@github-ui/react-core/test-utils'
import {mockPromptEvalsState} from './mocks'
import {screen, within} from '@testing-library/react'
import type {PlaygroundMessage} from '../../../../types'
import {mockModel} from '../../../playground/__tests__/mocks'
import {PromptEvalsManagerContext, type PromptEvalsManager} from '../../prompt-evals-manager'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlag = jest.mocked(useFeatureFlag)

const playgroundUrl = 'azure-ai-playground-url.com'
const mockModelClient = new AzureModelClient(playgroundUrl)

const initialState = mockPromptEvalsState()

const evalsClearUserSystemPromptAndVariables = jest.fn().mockName('evalsClearUserSystemPromptAndVariables')
const resetHistory = jest.fn().mockName('resetHistory')
const sendMessage = jest.fn().mockName('sendMessage')
const evalsAddRow = jest.fn().mockName('evalsAddRow')
mockModelClient.stopStreamingMessages = jest.fn().mockName('stopStreamingMessages')

const userMessage = {
  role: 'user',
  message: 'test message',
  timestamp: new Date('2024-01-01T00:00:00+00:00'),
} satisfies PlaygroundMessage

const assistantMessage = {
  role: 'assistant',
  message: 'test response',
  timestamp: new Date('2024-01-01T00:00:01+00:00'),
} satisfies PlaygroundMessage

describe('Prompt', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders the blank state when there are no messages', () => {
    renderComponent(<Prompt modelClient={mockModelClient} />)
    expect(screen.queryByTestId('playground-chat-message-header')).not.toBeInTheDocument()
    expect(screen.queryByTestId('github-avatar')).not.toBeInTheDocument()
    expect(screen.getByText('Iterate on your prompt')).toBeInTheDocument()
  })

  test('renders a user message with their name and avatar', () => {
    renderComponent(<Prompt modelClient={mockModelClient} />, [userMessage])
    expect(screen.getByTestId('playground-chat-message-header')).toBeInTheDocument()
    expect(screen.getByTestId('github-avatar')).toBeInTheDocument()
    expect(screen.getByText('test user')).toBeInTheDocument()
    expect(screen.getByTestId('message-timestamp')).toBeInTheDocument()
    expect(screen.getByText('test message')).toBeInTheDocument()
  })

  test('renders an assistant message with the model name and avatar', () => {
    renderComponent(<Prompt modelClient={mockModelClient} />, [userMessage, assistantMessage])
    const header = screen.getAllByTestId('playground-chat-message-header')

    expect(header).toHaveLength(2)
    expect(screen.getByTestId('github-avatar')).toBeInTheDocument()
    expect(screen.getByText('test user')).toBeInTheDocument()

    const assistantContainer = header[1]
    expect(assistantContainer).toHaveTextContent(mockModel.friendly_name)
    within(assistantContainer!).getByTestId('models-avatar')
    expect(screen.getAllByTestId('message-timestamp')).toHaveLength(2)
    expect(screen.getByText('test response')).toBeInTheDocument()
    expect(screen.queryByText('Responding...')).not.toBeInTheDocument()
  })

  test("renders 'Responding...' when loading", () => {
    renderComponent(<Prompt modelClient={mockModelClient} />, [userMessage, assistantMessage], true)
    const header = screen.getAllByTestId('playground-chat-message-header')
    expect(header).toHaveLength(2)
    expect(screen.getByTestId('github-avatar')).toBeInTheDocument()
    expect(screen.getByText('test user')).toBeInTheDocument()
    const assistantContainer = header[1]
    expect(assistantContainer).toHaveTextContent(mockModel.friendly_name)
    within(assistantContainer!).getByTestId('models-avatar')
    expect(screen.getAllByTestId('message-timestamp')).toHaveLength(1)
    expect(screen.getByText('test response')).toBeInTheDocument()
    expect(screen.getByText('Responding...')).toBeInTheDocument()
  })

  test('when user clicks run button, replaces vars with values and sends the prompt to the model client', async () => {
    const {user} = renderComponent(<Prompt modelClient={mockModelClient} />, [], false, {
      variables: {foo: 'bar'},
      prompt: 'test prompt {{foo}}',
      systemPrompt: 'test system prompt',
    })

    const runButton = screen.getByRole('button', {name: /Run/i})
    expect(runButton).toBeInTheDocument()
    await user.click(runButton)

    expect(sendMessage).toHaveBeenCalledTimes(1)
    expect(sendMessage).toHaveBeenCalledWith(
      initialState.model,
      mockModelClient,
      'test system prompt',
      'test prompt bar',
    )
  })

  test('if message pair flag enabled and message pair is present, replaces vars with values and sends the prompt to the model client', async () => {
    mockUseFeatureFlag.mockImplementation(flag => flag === 'github_models_prompt_message_pair')
    const {user} = renderComponent(<Prompt modelClient={mockModelClient} />, [], false, {
      variables: {foo: 'bar'},
      prompt: 'test prompt {{foo}}',
      systemPrompt: 'test system prompt',
      messagePairs: [{assistant: 'assistant message {{foo}}', user: 'user message {{foo}}'}],
    })

    const runButton = screen.getByRole('button', {name: /Run/i})
    expect(runButton).toBeInTheDocument()
    await user.click(runButton)

    expect(sendMessage).toHaveBeenCalledTimes(1)
    expect(sendMessage).toHaveBeenCalledWith(
      initialState.model,
      mockModelClient,
      'test system prompt',
      'test prompt bar',
      [],
      [{assistant: 'assistant message bar', user: 'user message bar'}],
    )
  })

  test('if message pair flag is not enabled, does not send message pairs to the model client', async () => {
    mockUseFeatureFlag.mockReturnValue(false)

    const {user} = renderComponent(<Prompt modelClient={mockModelClient} />, [], false, {
      variables: {foo: 'bar'},
      prompt: 'test prompt {{foo}}',
      systemPrompt: 'test system prompt',
      messagePairs: [{assistant: 'assistant message {{foo}}', user: 'user message {{foo}}'}],
    })

    const runButton = screen.getByRole('button', {name: /Run/i})
    expect(runButton).toBeInTheDocument()
    await user.click(runButton)

    expect(sendMessage).toHaveBeenCalledTimes(1)
    expect(sendMessage).toHaveBeenCalledWith(
      initialState.model,
      mockModelClient,
      'test system prompt',
      'test prompt bar',
    )
  })

  test('displays system and user prompt', () => {
    renderComponent(<Prompt modelClient={mockModelClient} />)

    expect(screen.getByRole('textbox', {name: 'System'})).toBeInTheDocument()
    expect(screen.getByRole('textbox', {name: 'User'})).toBeInTheDocument()
  })

  test('renders PromptAutocompleteInput for system and user prompt', async () => {
    renderComponent(<Prompt modelClient={mockModelClient} />)
    expect(screen.getByTestId('system-autocomplete-component')).toBeInTheDocument()
    expect(screen.getByTestId('prompt-autocomplete-component')).toBeInTheDocument()

    expect(screen.queryByTestId('system-prompt-textarea')).not.toBeInTheDocument()
    expect(screen.queryByTestId('user-prompt-textarea')).not.toBeInTheDocument()
  })

  test('clears the prompt, variables and chat when trash icon is clicked', async () => {
    const {user} = renderComponent(<Prompt modelClient={mockModelClient} />, [userMessage, assistantMessage], false, {
      variables: {foo: 'bar'},
      prompt: 'test prompt {{foo}}',
      systemPrompt: 'test system prompt',
    })
    expect(screen.getByText('test response')).toBeInTheDocument()

    const userPrompt = screen.getByRole('textbox', {name: 'User'})
    expect(userPrompt).toHaveValue('test prompt {{foo}}')

    const systemPrompt = screen.getByRole('textbox', {name: 'System'})
    expect(systemPrompt).toHaveValue('test system prompt')

    const editVariablesButton = await screen.findByTestId('edit-variables')
    await user.click(editVariablesButton)

    const fooTextbox = screen.getByRole('textbox', {name: '{{foo}}'})
    expect(fooTextbox).toHaveValue('bar')

    const cancelEditVariablesButton = await screen.findByRole('button', {name: 'Cancel'})
    await user.click(cancelEditVariablesButton)

    const clearPromptButton = await screen.findByTestId('clear-prompt')
    await user.click(clearPromptButton)

    expect(evalsClearUserSystemPromptAndVariables).toHaveBeenCalledTimes(1)
    expect(resetHistory).toHaveBeenCalledTimes(1)
    expect(mockModelClient.stopStreamingMessages).toHaveBeenCalledTimes(1)
  })

  test('renders add message pair button when feature flag is enabled', () => {
    mockUseFeatureFlag.mockImplementation(flag => flag === 'github_models_prompt_message_pair')

    renderComponent(<Prompt modelClient={mockModelClient} />)
    expect(screen.getByRole('button', {name: 'Add message pair'})).toBeInTheDocument()
  })

  test('does not render add message pair button when feature flag is disabled', () => {
    mockUseFeatureFlag.mockReturnValue(false)

    renderComponent(<Prompt modelClient={mockModelClient} />)
    expect(screen.queryByRole('button', {name: 'Add message pair'})).not.toBeInTheDocument()
  })
})

function renderComponent(component: JSX.Element, messages: PlaygroundMessage[] = [], isLoading = false, props = {}) {
  const currentUser: Partial<UserHookPayload['current_user']> = {name: 'test user'}
  const stateValue = {...initialState, model: {...initialState.model, messages, isLoading}, ...props}

  const manager = {} as PromptEvalsManager
  manager.evalsClearUserSystemPromptAndVariables = evalsClearUserSystemPromptAndVariables
  manager.resetHistory = resetHistory
  manager.sendMessage = sendMessage
  manager.evalsAddRow = evalsAddRow

  return render(
    <PromptEvalsStateProvider state={stateValue}>
      <PromptEvalsManagerContext.Provider value={manager}>{component}</PromptEvalsManagerContext.Provider>
    </PromptEvalsStateProvider>,
    {
      appPayload: {current_user: currentUser},
    },
  )
}
