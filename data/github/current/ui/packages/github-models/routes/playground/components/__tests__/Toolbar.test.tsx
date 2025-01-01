import {within} from '@testing-library/react'
import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {Toolbar, type ToolbarProps} from '../Toolbar'
import {mockGettingStarted, mockLocalStorageUiState, mockModel} from '../../__tests__/mocks'
import {mockModelState, mockPlaygroundState, mockStoredMessage, setupMatchMediaMock} from './mocks'
import {Panel, type PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import {PlaygroundContentOption} from '../types'
import {MessageHistoryProvider} from '../MessageHistoryContext'
import type {PlaygroundMessage, PlaygroundState, TokenUsage} from '../../../../types'
import {mockResizeObserver, mockSDK} from '../GettingStartedDialog/__tests__/mocks'

jest.mock('@github-ui/react-core/use-feature-flag')

const resetHistory = jest.fn().mockName('resetHistory')
const setMessages = jest.fn().mockName('setMessages')
const setSyncInputs = jest.fn().mockName('setSyncInputs')
const setTokenUsage = jest.fn().mockName('setTokenUsage')
const handleClearHistory = jest.fn().mockName('handleClearHistory')

const getToolbarProps = (props: Partial<ToolbarProps> = {}): ToolbarProps => ({
  onComparisonMode: false,
  option: PlaygroundContentOption.CHAT,
  position: Panel.Main,
  modelState: mockModelState({messages: [mockStoredMessage]}),
  uiState: {...mockLocalStorageUiState, preferredLanguage: 'js', preferredSdk: 'azure-ai-inference'},
  handleSelectLanguage: jest.fn(),
  handleSelectSDK: jest.fn(),
  handleClearHistory,
  ...props,
})

describe('Toolbar', () => {
  beforeEach(() => {
    setupMatchMediaMock()

    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all the Toolbar tests are run:
    mockResizeObserver()
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders Chat option when history cannot be restored but there is a message', async () => {
    const {container, user} = render(
      <Toolbar {...getToolbarProps({onComparisonMode: true})}>foo toolbar content</Toolbar>,
      {playgroundState: mockPlaygroundState({models: []})},
    )

    const resetHistoryButton = within(container).getByRole('button', {name: 'Reset chat history'})
    expect(resetHistoryButton).toBeInTheDocument()
    expect(resetHistoryButton).toBeEnabled()
    expect(within(container).queryByTestId('restore-history-button')).not.toBeInTheDocument()
    expect(within(container).queryByText('foo toolbar content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(resetHistory).not.toHaveBeenCalled()

    await user.click(resetHistoryButton)

    expect(handleClearHistory).toHaveBeenCalledTimes(1)
    expect(setMessages).not.toHaveBeenCalled()
    expect(setTokenUsage).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
  })

  test('renders Chat option when history cannot be restored and there are no messages', () => {
    const modelState = mockModelState({messages: []})

    const {container} = render(<Toolbar {...getToolbarProps({modelState})}>foo toolbar content</Toolbar>, {
      playgroundState: mockPlaygroundState({models: [modelState]}),
    })

    const resetHistoryButton = within(container).getByRole('button', {name: 'Reset chat history', hidden: true})
    expect(resetHistoryButton).toBeInTheDocument()
    expect(resetHistoryButton).toBeDisabled()
    expect(within(container).queryByTestId('restore-history-button')).not.toBeInTheDocument()
    expect(within(container).queryByText('foo toolbar content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(resetHistory).not.toHaveBeenCalled()
    expect(setMessages).not.toHaveBeenCalled()
    expect(setTokenUsage).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
  })

  test('renders Chat option when history can be restored', async () => {
    const modelState = mockModelState({messages: []})
    const history = [mockStoredMessage]
    const tokenUsageHistory = {
      lastMessageInputTokens: 150,
      totalInputTokens: 10,
      lastMessageOutputTokens: 5,
      totalOutputTokens: 20,
    }

    const {container, user} = render(<Toolbar {...getToolbarProps({modelState})}>foo toolbar content</Toolbar>, {
      initialMessages: history,
      initialTokenUsage: tokenUsageHistory,
      playgroundState: mockPlaygroundState({models: [modelState]}),
    })

    const resetHistoryButton = within(container).getByRole('button', {name: 'Reset chat history', hidden: true})
    expect(resetHistoryButton).toBeInTheDocument()
    expect(resetHistoryButton).toBeDisabled()
    const restoreHistoryButton = within(container).getByTestId('restore-history-button')
    expect(restoreHistoryButton).toBeInTheDocument()
    expect(within(container).queryByText('foo toolbar content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(setMessages).not.toHaveBeenCalled()
    expect(setTokenUsage).not.toHaveBeenCalled()

    await user.click(restoreHistoryButton)

    expect(setMessages).toHaveBeenCalledTimes(1)
    expect(setMessages).toHaveBeenCalledWith(Panel.Main, history)
    expect(setTokenUsage).toHaveBeenCalledTimes(1)
    expect(setTokenUsage).toHaveBeenCalledWith(Panel.Main, tokenUsageHistory)
    expect(resetHistory).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
  })

  test('renders Chat option when a model can be added for comparison', async () => {
    const modelName = 'hello-world-model'
    const catalogData = Object.assign({}, mockModel, {name: modelName})
    const modelState = mockModelState({messages: [], catalogData})

    const {container} = render(<Toolbar {...getToolbarProps({modelState})}>foo toolbar content</Toolbar>, {
      playgroundState: mockPlaygroundState({models: [modelState]}),
      search: '?preset=foo&p=bar&other=baz',
    })

    const resetHistoryButton = within(container).getByRole('button', {name: 'Reset chat history', hidden: true})
    expect(resetHistoryButton).toBeInTheDocument()
    expect(resetHistoryButton).toBeDisabled()
    expect(within(container).queryByTestId('restore-history-button')).not.toBeInTheDocument()
    expect(within(container).queryByText('foo toolbar content')).not.toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(setSyncInputs).not.toHaveBeenCalled()
  })

  test('renders Code option', () => {
    const selectedLanguage = 'ruby'
    const gettingStarted = Object.assign({}, mockGettingStarted)
    const languageName = 'Ruby'
    const sdkName = 'My Ruby SDK'
    const selectedSDK = 'my-ruby-sdk'
    gettingStarted[selectedLanguage] = {
      name: languageName,
      sdks: {[selectedSDK]: mockSDK({name: sdkName})},
    }
    const modelState = mockModelState({gettingStarted})
    const playgroundState = mockPlaygroundState()
    const uiState = {...mockLocalStorageUiState, preferredLanguage: selectedLanguage, preferredSdk: selectedSDK}

    const {container} = render(
      <Toolbar {...getToolbarProps({modelState, uiState, option: PlaygroundContentOption.CODE})}>
        foo toolbar content
      </Toolbar>,
      {playgroundState},
    )

    expect(within(container).getByTestId('playground-language-button')).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: languageName})).toBeInTheDocument()
    expect(within(container).getByTestId('playground-sdk-button')).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: sdkName})).toBeInTheDocument()
    expect(within(container).queryByTestId('restore-history-button')).not.toBeInTheDocument()
    expect(within(container).queryByText('foo toolbar content')).not.toBeInTheDocument()
    expect(resetHistory).not.toHaveBeenCalled()
    expect(setMessages).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
  })

  test('renders JSON option when history cannot be restored', () => {
    const modelState = mockModelState()

    const {container} = render(
      <Toolbar {...getToolbarProps({option: PlaygroundContentOption.JSON, modelState})}>foo toolbar content</Toolbar>,
      {initialMessages: []},
    )

    expect(within(container).queryByTestId('restore-history-button')).not.toBeInTheDocument()
    expect(within(container).getByText('foo toolbar content')).toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(resetHistory).not.toHaveBeenCalled()
    expect(setMessages).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
  })

  test('renders JSON option when history can be restored', () => {
    const modelState = mockModelState({messages: []})

    const {container} = render(
      <Toolbar {...getToolbarProps({option: PlaygroundContentOption.JSON, modelState})}>foo toolbar content</Toolbar>,
      {initialMessages: [mockStoredMessage], playgroundState: mockPlaygroundState({models: [modelState]})},
    )

    expect(within(container).getByTestId('restore-history-button')).toBeInTheDocument()
    expect(within(container).getByText('foo toolbar content')).toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(resetHistory).not.toHaveBeenCalled()
    expect(setMessages).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
  })
})

interface renderOpts extends TestRenderOptions {
  initialMessages?: PlaygroundMessage[]
  initialTokenUsage?: TokenUsage
  playgroundState?: PlaygroundState
}

function render(
  component: JSX.Element,
  {initialMessages, initialTokenUsage, playgroundState, ...rest}: renderOpts = {},
) {
  const manager = {} as PlaygroundManager
  manager.resetHistory = resetHistory
  manager.setMessages = setMessages
  manager.setSyncInputs = setSyncInputs
  manager.setTokenUsage = setTokenUsage

  return htmlRender(component, {
    wrapper: ({children}) => (
      <PlaygroundManagerProvider manager={manager}>
        <PlaygroundStateProvider state={playgroundState ?? mockPlaygroundState()}>
          <MessageHistoryProvider initialMessages={initialMessages} initialTokenUsage={initialTokenUsage}>
            {children}
          </MessageHistoryProvider>
        </PlaygroundStateProvider>
      </PlaygroundManagerProvider>
    ),
    ...rest,
  })
}
