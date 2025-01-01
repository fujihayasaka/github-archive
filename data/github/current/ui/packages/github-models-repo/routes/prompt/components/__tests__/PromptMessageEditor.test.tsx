import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {PromptMessageEditor} from '../PromptMessageEditor'
import type {Message} from '../../types'
import {mockModel, mockResizeObserver} from '../../../../test-utils/mock-data'

const mockVerifiedFetchJSON = jest.fn().mockName('verifiedFetchJSON')
const updateMessages = jest.fn().mockName('updateMessages')

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => {
  return {
    verifiedFetchJSON: (...args: unknown[]) => mockVerifiedFetchJSON(...args),
  }
})

describe('PromptMessageEditor', () => {
  beforeEach(() => {
    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all tests are run.
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  it('renders when a system prompt is not supported', async () => {
    const model = mockModel()
    const messages: Message[] = [{role: 'user', message: 'Hello friends', timestamp: new Date()}]

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => ({modelInputSchema: {capabilities: {systemPrompt: false}}}),
    })

    render(<PromptMessageEditor selectedModel={model} messages={messages} updateMessages={updateMessages} />)

    expect(updateMessages).not.toHaveBeenCalled()
    const userPromptInput = await screen.findByRole('textbox', {name: 'User prompt'})
    expect(userPromptInput).toBeInTheDocument()
    expect(userPromptInput).toHaveValue('Hello friends')
    expect(screen.queryByRole('textbox', {name: 'System prompt'})).not.toBeInTheDocument()
  })

  it('renders when a system prompt is supported', async () => {
    const model = mockModel()
    const messages: Message[] = [
      {role: 'system', message: 'You are a cantankerous wizard.', timestamp: new Date()},
      {role: 'user', message: '', timestamp: new Date()},
    ]

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => ({modelInputSchema: {capabilities: {systemPrompt: true}}}),
    })

    render(<PromptMessageEditor selectedModel={model} messages={messages} updateMessages={updateMessages} />)

    expect(updateMessages).not.toHaveBeenCalled()
    const userPromptInput = await screen.findByRole('textbox', {name: 'User prompt'})
    expect(userPromptInput).toBeInTheDocument()
    expect(userPromptInput).toHaveValue('')
    const systemPromptInput = screen.getByRole('textbox', {name: 'System prompt'})
    expect(systemPromptInput).toBeInTheDocument()
    expect(systemPromptInput).toHaveValue('You are a cantankerous wizard.')
  })

  it('allows updating a prompt', async () => {
    const model = mockModel()
    const messages: Message[] = [{role: 'user', message: '', timestamp: new Date()}]

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => ({modelInputSchema: {capabilities: {systemPrompt: false}}}),
    })

    const {user} = render(
      <PromptMessageEditor selectedModel={model} messages={messages} updateMessages={updateMessages} />,
    )

    expect(updateMessages).not.toHaveBeenCalled()
    const userPromptInput = await screen.findByRole('textbox', {name: 'User prompt'})
    expect(userPromptInput).toBeInTheDocument()

    await user.type(userPromptInput, 'hi')

    expect(updateMessages).toHaveBeenCalledWith([
      {
        role: 'user',
        message: 'h',
        timestamp: expect.any(Date),
      },
    ])
    expect(updateMessages).toHaveBeenCalledWith([
      {
        role: 'user',
        message: 'i',
        timestamp: expect.any(Date),
      },
    ])
  })

  it('renders only the first system/user pair and excludes message pairs', async () => {
    const model = mockModel()
    const messages: Message[] = [
      {role: 'system', message: 'You are a helpful assistant.', timestamp: new Date()},
      {role: 'user', message: 'What is the weather?', timestamp: new Date()},
      // These are message pairs that should NOT be rendered by PromptMessageEditor
      {role: 'assistant', message: 'It is sunny today.', timestamp: new Date()},
      {role: 'user', message: 'What about tomorrow?', timestamp: new Date()},
      {role: 'assistant', message: 'Tomorrow will be cloudy.', timestamp: new Date()},
      {role: 'user', message: 'Should I bring an umbrella?', timestamp: new Date()},
    ]

    mockVerifiedFetchJSON.mockResolvedValue({
      ok: true,
      json: () => ({modelInputSchema: {capabilities: {systemPrompt: true}}}),
    })

    render(<PromptMessageEditor selectedModel={model} messages={messages} updateMessages={updateMessages} />)

    // Should render the system prompt
    const systemPromptInput = await screen.findByRole('textbox', {name: 'System prompt'})
    expect(systemPromptInput).toBeInTheDocument()
    expect(systemPromptInput).toHaveValue('You are a helpful assistant.')

    // Should render the first user prompt
    const userPromptInput = screen.getByRole('textbox', {name: 'User prompt'})
    expect(userPromptInput).toBeInTheDocument()
    expect(userPromptInput).toHaveValue('What is the weather?')

    // Should NOT render any assistant prompts (these are handled by PromptMessagePair)
    expect(screen.queryByRole('textbox', {name: 'Assistant prompt'})).not.toBeInTheDocument()

    // Should NOT render any additional user prompts beyond the first one
    const allUserInputs = screen.getAllByRole('textbox', {name: 'User prompt'})
    expect(allUserInputs).toHaveLength(1)
  })
})
