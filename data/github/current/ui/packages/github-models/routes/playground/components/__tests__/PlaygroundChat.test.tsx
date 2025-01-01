import {tasksReducer, Panel, PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'
import {initialPlaygroundState, PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import {
  mockLocalStorageUiState,
  mockModel,
  mockModelState,
  mockModelInputSchema,
  mockTokenUsage,
} from '../../__tests__/mocks'
import {mockModelState as mockState, getImageModelState} from './mocks'
import {AzureModelClient} from '../../../../utils/azure-model-client'
import {ModelClientProvider} from '../../contexts/ModelClientContext'
import {useMemo, useReducer, type PropsWithChildren} from 'react'
import {render} from '@github-ui/react-core/test-utils'
import {testFile} from '@github-ui/attachments/test-utils'
import {PlaygroundChat} from '../PlaygroundChat'
import {screen, act, within, waitFor} from '@testing-library/react'
import type {PlaygroundMessage, PlaygroundState} from '../../../../types'
import {fireFileDropEvent} from './test-utils'
import type {UserHookPayload} from '@github-ui/use-user'

const playgroundUrl = 'azure-ai-playground-url.com'

const allowedModel1 = {...mockModel, name: 'allowed-model-1', friendly_name: 'Allowed Model 1', id: 'allowed-model-1'}
const allowedModel2 = {...mockModel, name: 'allowed-model-2', friendly_name: 'Allowed Model 2', id: 'allowed-model-2'}
const disallowedModel = {
  ...mockModel,
  name: 'disallowed-model',
  friendly_name: 'Disallowed Model',
  id: 'disallowed-model',
}

jest.mock('../../hooks/use-query-models', () => ({
  useLowRateLimitTierModels: jest.fn(() => ({
    data: [allowedModel1, allowedModel2, disallowedModel],
  })),
}))

const repoModels = [allowedModel1, allowedModel2]

jest.mock('@github-ui/github-models-repo/UseFilteredModels', () => ({
  useFilteredModels: jest.fn(() => ({
    availableModels: repoModels,
    isLoadingModels: false,
  })),
}))

const firstMessage = {
  role: 'user',
  message: 'test message',
  timestamp: new Date('2024-01-01T00:00:00+00:00'),
} satisfies PlaygroundMessage

const secondMessage = {
  role: 'assistant',
  message: 'test response',
  timestamp: new Date('2024-01-01T00:00:01+00:00'),
} satisfies PlaygroundMessage

const thirdMessage = {
  role: 'user',
  message: 'test message 2',
  timestamp: new Date('2024-01-01T00:00:02+00:00'),
} satisfies PlaygroundMessage

const fourthMessage = {
  role: 'assistant',
  message: 'test response 2',
  timestamp: new Date('2024-01-01T00:00:03+00:00'),
} satisfies PlaygroundMessage

const errorMessage = {
  role: 'error',
  message: 'An error occurred',
  timestamp: new Date('2024-01-01T00:00:04+00:00'),
} satisfies PlaygroundMessage

const getProps = (props: Partial<typeof PlaygroundChat> = {}) => ({
  model: {...mockModelState, messages: [firstMessage, secondMessage, thirdMessage, fourthMessage]},
  position: Panel.Main,
  showSidebar: false,
  onComparisonMode: false,
  handleSetSidebarTab: jest.fn(),
  handleShowSidebar: jest.fn(),
  stopStreamingMessages: jest.fn(),
  uiState: mockLocalStorageUiState,
  handleSelectLanguage: jest.fn(),
  handleSelectSDK: jest.fn(),
  repository: undefined,
  ...props,
})

const setModelState = jest.fn()
const resetParamsAndSystemPrompt = jest.fn().mockName('resetParamsAndSystemPrompt')

const PlaygroundWrapper = ({
  children,
  initialPlaygroundState: initialPlaygroundStateProp,
}: PropsWithChildren<{initialPlaygroundState?: PlaygroundState}>) => {
  const [playgroundState, playgroundDispatch] = useReducer(
    tasksReducer,
    initialPlaygroundStateProp ?? initialPlaygroundState(),
  )

  // Ensure PlaygroundManager is not recreated on every render
  const manager = useMemo(() => new PlaygroundManager(playgroundDispatch), [playgroundDispatch])
  manager.setModelState = setModelState
  manager.resetParamsAndSystemPrompt = resetParamsAndSystemPrompt
  const mockModelClient = new AzureModelClient(playgroundUrl)
  return (
    <PlaygroundStateProvider state={playgroundState}>
      <PlaygroundManagerProvider manager={manager}>
        <ModelClientProvider modelClient={mockModelClient}>{children}</ModelClientProvider>
      </PlaygroundManagerProvider>
    </PlaygroundStateProvider>
  )
}

describe('PlaygroundChat', () => {
  test('the edit button on last message resets last message pair and populates chat input', async () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {lastMessageOutputTokens: 100, totalOutputTokens: 400})
    const modelState = Object.assign({}, mockModelState, {
      messages: [firstMessage, secondMessage, thirdMessage, fourthMessage],
      tokenUsage,
    })

    const {container, user} = render(
      <PlaygroundWrapper>
        <PlaygroundChat {...getProps({model: modelState})} />
      </PlaygroundWrapper>,
    )

    const editPromptMenu = within(container).getByRole('button', {name: 'Edit prompt menu'})
    expect(editPromptMenu).toBeInTheDocument()

    await user.click(editPromptMenu)

    const editButton = screen.getByRole('menuitem', {name: 'Edit prompt'})

    await user.click(editButton)

    expect(setModelState).toHaveBeenCalledWith(
      0,
      expect.objectContaining({
        chatInput: 'test message 2',
        messages: [firstMessage, secondMessage],
        tokenUsage: {...tokenUsage, totalOutputTokens: 300, lastMessageOutputTokens: 0},
      }),
    )
  })

  test('the edit prompt button should return focus to the chat input', async () => {
    const tokenUsage = Object.assign({}, mockTokenUsage, {lastMessageOutputTokens: 100, totalOutputTokens: 400})
    const modelState = Object.assign({}, mockModelState, {
      messages: [firstMessage, secondMessage, thirdMessage, fourthMessage],
      tokenUsage,
    })

    const {container, user} = render(
      <PlaygroundWrapper>
        <PlaygroundChat {...getProps({model: modelState})} />
      </PlaygroundWrapper>,
    )

    const promptInput = screen.getByRole<HTMLTextAreaElement>('textbox', {name: 'Prompt'})
    await user.type(promptInput, 'Hello there')

    const editPromptMenu = within(container).getByRole('button', {name: 'Edit prompt menu'})
    expect(editPromptMenu).toBeInTheDocument()

    await user.click(editPromptMenu)

    const editButton = screen.getByRole('menuitem', {name: 'Edit prompt'})

    await user.click(editButton)

    await waitFor(() => {
      expect(promptInput).toHaveFocus()
    })
  })

  test('should allow image attachments', async () => {
    const model1 = getImageModelState(mockModelState)
    const model2 = getImageModelState(mockModelState)

    const {container} = render(
      <PlaygroundWrapper initialPlaygroundState={{syncInputs: true, models: [model1, model2]}}>
        <PlaygroundChat {...getProps({onComparisonMode: true, model: model1})} />
        <PlaygroundChat {...getProps({onComparisonMode: true, model: model2})} />
      </PlaygroundWrapper>,
    )

    const el = within(container).getAllByTestId('playground-chat-attachment-dropzone')
    expect(el).toHaveLength(2)

    fireFileDropEvent([testFile(), testFile(), testFile()], el[0])

    await act(async () => {
      // pretend to upload
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    // 6, or 3 per chat.
    expect(within(container).getAllByAltText('attachment')).toHaveLength(6)
  })

  test("the comparison mode should limit attachments to the model's capabilities", async () => {
    const model1 = getImageModelState(mockModelState)
    const model2 = getImageModelState(mockModelState)
    model2.modelInputSchema!.capabilities = {chat: {imagesPerTurn: 2}}

    const {container} = render(
      <PlaygroundWrapper initialPlaygroundState={{syncInputs: true, models: [model1, model2]}}>
        <PlaygroundChat {...getProps({onComparisonMode: true, model: model1})} />
        <PlaygroundChat {...getProps({onComparisonMode: true, model: model2})} />
      </PlaygroundWrapper>,
    )

    const el = within(container).getAllByTestId('playground-chat-attachment-dropzone')
    expect(el).toHaveLength(2)

    fireFileDropEvent([testFile(), testFile(), testFile()], el[0])

    await act(async () => {
      // pretend to upload
      await new Promise(resolve => setTimeout(resolve, 50))
    })

    expect(within(container).getAllByText('Sorry, only up to 2 files per message are supported.')).toHaveLength(2)
  })

  test('renders a user message with their name and avatar', () => {
    const currentUser: Partial<UserHookPayload['current_user']> = {name: 'test user'}
    render(
      <PlaygroundWrapper>
        <PlaygroundChat {...getProps({model: {...mockModelState, messages: [firstMessage]}})} />
      </PlaygroundWrapper>,
      {appPayload: {current_user: currentUser}},
    )

    expect(screen.getByTestId('playground-chat-message-header')).toBeInTheDocument()
    expect(screen.getByTestId('github-avatar')).toBeInTheDocument()
    expect(screen.queryByTestId('publisher-avatar')).not.toBeInTheDocument()
    expect(screen.getByText('test user')).toBeInTheDocument()
    expect(screen.getByTestId('message-timestamp')).toBeInTheDocument()
    expect(screen.getByText('test message')).toBeInTheDocument()
    expect(screen.queryByText('Responding...')).not.toBeInTheDocument()
  })

  test('renders an assistant message with the model name and avatar', () => {
    const userName = 'test user'
    const currentUser: Partial<UserHookPayload['current_user']> = {name: userName}
    render(
      <PlaygroundWrapper>
        <PlaygroundChat {...getProps({model: {...mockModelState, messages: [firstMessage, secondMessage]}})} />
      </PlaygroundWrapper>,
      {appPayload: {current_user: currentUser}},
    )

    expect(screen.getAllByTestId('playground-chat-message-header')).toHaveLength(2)
    expect(screen.getByTestId('github-avatar')).toBeInTheDocument()
    expect(screen.getByTestId('publisher-avatar')).toBeInTheDocument()
    expect(screen.getByText(mockModel.friendly_name)).toBeInTheDocument()
    expect(screen.getByText(userName)).toBeInTheDocument()
    expect(screen.getAllByTestId('message-timestamp')).toHaveLength(2)
    expect(screen.getByText('test response')).toBeInTheDocument()
    expect(screen.queryByText('Responding...')).not.toBeInTheDocument()
  })

  test('renders loading state for assistant message', () => {
    const userName = 'test user'
    const currentUser: Partial<UserHookPayload['current_user']> = {name: userName}
    render(
      <PlaygroundWrapper>
        <PlaygroundChat
          {...getProps({model: {...mockModelState, isLoading: true, messages: [firstMessage, secondMessage]}})}
        />
      </PlaygroundWrapper>,
      {appPayload: {current_user: currentUser}},
    )

    expect(screen.getAllByTestId('playground-chat-message-header')).toHaveLength(2)
    expect(screen.getByTestId('github-avatar')).toBeInTheDocument()
    expect(screen.getByTestId('publisher-avatar')).toBeInTheDocument()
    expect(screen.getByText(mockModel.friendly_name)).toBeInTheDocument()
    expect(screen.getByText(userName)).toBeInTheDocument()
    expect(screen.getAllByTestId('message-timestamp')).toHaveLength(1)
    expect(screen.getByText('Responding...')).toBeInTheDocument()
    expect(screen.getByText('test response')).toBeInTheDocument()
  })

  // https://github.com/github/models/issues/935
  test('hides message header for an error message if it occurs after an assistant message', () => {
    const userName = 'test user'
    const currentUser: Partial<UserHookPayload['current_user']> = {name: userName}
    const messages = [firstMessage, secondMessage, errorMessage]
    render(
      <PlaygroundWrapper>
        <PlaygroundChat
          {...getProps({
            model: {
              ...mockModelState,
              messages,
            },
          })}
        />
      </PlaygroundWrapper>,
      {appPayload: {current_user: currentUser}},
    )

    expect(screen.getAllByTestId('playground-chat-message-header')).toHaveLength(messages.length - 1)
    expect(screen.getAllByTestId('github-avatar')).toHaveLength(1)
    expect(screen.getAllByTestId('publisher-avatar')).toHaveLength(1)
    expect(screen.getByText(mockModel.friendly_name)).toBeInTheDocument()
    expect(screen.getByText(userName)).toBeInTheDocument()
    expect(screen.getByText('test response')).toBeInTheDocument()
    expect(screen.getByTestId('playground-error')).toBeInTheDocument()
    expect(screen.getByText('An error occurred')).toBeInTheDocument()
  })

  test('shows message header for an error message if it does not occur after an assistant message', () => {
    const userName = 'test user'
    const currentUser: Partial<UserHookPayload['current_user']> = {name: userName}
    const messages = [firstMessage, errorMessage]
    render(
      <PlaygroundWrapper>
        <PlaygroundChat
          {...getProps({
            model: {
              ...mockModelState,
              messages,
            },
          })}
        />
      </PlaygroundWrapper>,
      {appPayload: {current_user: currentUser}},
    )

    expect(screen.getAllByTestId('playground-chat-message-header')).toHaveLength(messages.length)
    expect(screen.getAllByTestId('github-avatar')).toHaveLength(1)
    expect(screen.getAllByTestId('publisher-avatar')).toHaveLength(1)
    expect(screen.getByText(mockModel.friendly_name)).toBeInTheDocument()
    expect(screen.getByText(userName)).toBeInTheDocument()
    expect(screen.getByTestId('playground-error')).toBeInTheDocument()
    expect(screen.getByText('An error occurred')).toBeInTheDocument()
  })

  test('renders Code and Raw tabs when on marketplace', () => {
    render(
      <PlaygroundWrapper>
        <PlaygroundChat {...getProps()} />
      </PlaygroundWrapper>,
      {pathname: '/marketplace/models/registry/name/playground'},
    )

    expect(screen.getByText('Code')).toBeInTheDocument()
    expect(screen.getByText('Raw')).toBeInTheDocument()
  })

  test('does not render Code and Raw tabs when on repo playground', () => {
    const repository = {
      name: 'repo-name',
      ownerLogin: 'owner-login',
    }

    render(
      <PlaygroundWrapper>
        <PlaygroundChat {...getProps({repository})} />
      </PlaygroundWrapper>,
    )

    expect(screen.queryByText('Code')).not.toBeInTheDocument()
    expect(screen.queryByText('Raw')).not.toBeInTheDocument()
  })

  test('renders Chat and Parameters tabs when on comparison view', () => {
    const model1 = mockModelState
    const model2 = {...mockModelState, catalogData: {...mockModel, name: 'model2'}}

    render(
      <PlaygroundWrapper initialPlaygroundState={{syncInputs: true, models: [model1, model2]}}>
        <PlaygroundChat {...getProps({onComparisonMode: true, model: model1})} />
        <PlaygroundChat {...getProps({onComparisonMode: true, model: model2})} />
      </PlaygroundWrapper>,
    )

    expect(screen.getAllByRole('button', {name: 'Chat'})).toHaveLength(2)
    expect(screen.getAllByRole('button', {name: 'Parameters'})).toHaveLength(2)
    const codeButtons = screen.getAllByRole('button', {name: 'Code'})
    expect(codeButtons[0]).toHaveClass('d-none')
    expect(codeButtons[1]).toHaveClass('d-none')
    const rawButtons = screen.getAllByRole('button', {name: 'Raw'})
    expect(rawButtons[0]).toHaveClass('d-none')
    expect(rawButtons[1]).toHaveClass('d-none')
    expect(screen.queryByTestId('legal-terms')).not.toBeInTheDocument()
  })

  test('only includes allowed models in quick actions menu', async () => {
    const repository = {
      name: 'repo-name',
      ownerLogin: 'owner-login',
    }

    const {container, user} = render(
      <PlaygroundWrapper>
        <PlaygroundChat
          {...getProps({
            model: {
              ...mockModelState,
              messages: [firstMessage, secondMessage, thirdMessage, fourthMessage],
            },
            repository,
          })}
        />
      </PlaygroundWrapper>,
    )

    const editButtonMenu = within(container).getByRole('button', {name: 'Edit prompt menu'})
    expect(editButtonMenu).toBeInTheDocument()
    expect(editButtonMenu).toBeEnabled()
    await user.click(editButtonMenu)

    const item = screen.getByRole('menuitem', {name: 'Make response cheaper'})
    await user.click(item)

    expect(screen.getByText(allowedModel1.friendly_name)).toBeInTheDocument()
    expect(screen.getByText(allowedModel2.friendly_name)).toBeInTheDocument()
    expect(screen.queryByText(disallowedModel.friendly_name)).not.toBeInTheDocument()
  })

  test('allows resetting inputs', async () => {
    const modelInputSchema = Object.assign({}, mockModelInputSchema, {capabilities: {systemPrompt: true}})
    const model1 = mockState({modelInputSchema, parametersHasChanges: true})
    const model2 = {...model1, catalogData: {...mockModel, name: 'model2'}}

    const {user} = render(
      <PlaygroundWrapper initialPlaygroundState={{syncInputs: true, models: [model1, model2]}}>
        <PlaygroundChat {...getProps({onComparisonMode: true, model: model1})} />
        <PlaygroundChat {...getProps({onComparisonMode: true, model: model2})} />
      </PlaygroundWrapper>,
    )

    const parametersButtons = screen.getAllByRole('button', {name: 'Parameters'})

    await user.click(parametersButtons[0]!)
    const resetInputsButton = screen.getByRole('button', {name: 'Reset to default inputs'})
    expect(resetInputsButton).toBeInTheDocument()
    expect(resetParamsAndSystemPrompt).not.toHaveBeenCalled()

    await user.click(resetInputsButton)

    expect(resetParamsAndSystemPrompt).toHaveBeenCalledTimes(2)
    expect(resetParamsAndSystemPrompt).toHaveBeenCalledWith(Panel.Main, {
      catalogData: model1.catalogData,
      modelInputSchema: model1.modelInputSchema,
      gettingStarted: model1.gettingStarted,
    })

    expect(resetParamsAndSystemPrompt).toHaveBeenCalledWith(Panel.Side, {
      catalogData: model1.catalogData,
      modelInputSchema: model1.modelInputSchema,
      gettingStarted: model1.gettingStarted,
    })
  })
})
