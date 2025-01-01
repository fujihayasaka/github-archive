import {within} from '@testing-library/react'
import {render as htmlRender, type TestRenderOptions, RouteContext} from '@github-ui/react-core/test-utils'
import {Toolbar} from '../Toolbar'
import {mockGettingStarted, mockModel} from '../../__tests__/mocks'
import {mockModelState, mockPlaygroundState, mockStoredMessage, setupMatchMediaMock} from './mocks'
import {Panel, type PlaygroundManager, PlaygroundManagerContext} from '../../../../utils/playground-manager'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import {PlaygroundContentOption} from '../types'
import {MessageHistoryProvider} from '../MessageHistoryContext'
import type {PlaygroundMessage, PlaygroundState} from '../../../../types'
import {mockResizeObserver, mockSDK} from '../GettingStartedDialog/__tests__/mocks'

jest.mock('@github-ui/react-core/use-feature-flag')

window.performance.mark = jest.fn()
window.performance.clearResourceTimings = jest.fn()

const resetHistory = jest.fn().mockName('resetHistory')
const setMessages = jest.fn().mockName('setMessages')
const setSyncInputs = jest.fn().mockName('setSyncInputs')
const getSideModel = jest.fn().mockName('getSideModel')
const stopStreamingMessages = jest.fn().mockName('stopStreamingMessages')

describe('Toolbar', () => {
  beforeEach(() => {
    setupMatchMediaMock()

    // Necessary to avoid a 'TypeError: observer.observe is not a function' error when all the Toolbar tests are run:
    mockResizeObserver()

    RouteContext.location = null
  })

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders Chat option when history cannot be restored but there is a message', async () => {
    const modelState = mockModelState({messages: [mockStoredMessage]})
    const position = Panel.Main

    const {container, user} = render(
      <Toolbar
        onComparisonMode
        option={PlaygroundContentOption.CHAT}
        position={position}
        modelState={modelState}
        stopStreamingMessages={stopStreamingMessages}
      >
        foo toolbar content
      </Toolbar>,
      {playgroundState: mockPlaygroundState({models: []})},
    )

    const resetHistoryButton = within(container).getByRole('button', {name: 'Reset chat history'})
    expect(resetHistoryButton).toBeInTheDocument()
    expect(resetHistoryButton).toBeEnabled()
    expect(within(container).queryByTestId('restore-history-button')).not.toBeInTheDocument()
    expect(within(container).queryByText('foo toolbar content')).not.toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Compare', hidden: true})).not.toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(resetHistory).not.toHaveBeenCalled()

    await user.click(resetHistoryButton)

    expect(resetHistory).toHaveBeenCalledTimes(1)
    expect(resetHistory).toHaveBeenCalledWith(position)
    expect(setMessages).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
    expect(getSideModel).not.toHaveBeenCalled()
  })

  test('renders Chat option when history cannot be restored and there are no messages', () => {
    const modelState = mockModelState({messages: []})

    const {container} = render(
      <Toolbar
        onComparisonMode={false}
        option={PlaygroundContentOption.CHAT}
        position={Panel.Main}
        modelState={modelState}
        stopStreamingMessages={stopStreamingMessages}
      >
        foo toolbar content
      </Toolbar>,
      {playgroundState: mockPlaygroundState({models: [modelState]})},
    )

    const resetHistoryButton = within(container).getByRole('button', {name: 'Reset chat history', hidden: true})
    expect(resetHistoryButton).toBeInTheDocument()
    expect(resetHistoryButton).toBeDisabled()
    expect(within(container).queryByTestId('restore-history-button')).not.toBeInTheDocument()
    expect(within(container).queryByText('foo toolbar content')).not.toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Compare', hidden: true})).toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(resetHistory).not.toHaveBeenCalled()
    expect(setMessages).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
    expect(getSideModel).not.toHaveBeenCalled()
  })

  test('renders Chat option when history can be restored', async () => {
    const modelState = mockModelState({messages: []})
    const position = Panel.Main
    const history = [mockStoredMessage]

    const {container, user} = render(
      <Toolbar
        onComparisonMode={false}
        option={PlaygroundContentOption.CHAT}
        position={position}
        modelState={modelState}
        stopStreamingMessages={stopStreamingMessages}
      >
        foo toolbar content
      </Toolbar>,
      {initialHistory: history, playgroundState: mockPlaygroundState({models: [modelState]})},
    )

    const resetHistoryButton = within(container).getByRole('button', {name: 'Reset chat history', hidden: true})
    expect(resetHistoryButton).toBeInTheDocument()
    expect(resetHistoryButton).toBeDisabled()
    const restoreHistoryButton = within(container).getByTestId('restore-history-button')
    expect(restoreHistoryButton).toBeInTheDocument()
    expect(within(container).queryByText('foo toolbar content')).not.toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Compare', hidden: true})).toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(setMessages).not.toHaveBeenCalled()

    await user.click(restoreHistoryButton)

    expect(setMessages).toHaveBeenCalledTimes(1)
    expect(setMessages).toHaveBeenCalledWith(position, history)
    expect(resetHistory).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
    expect(getSideModel).not.toHaveBeenCalled()
  })

  test('renders Chat option when a model can be added for comparison', async () => {
    const modelName = 'hello-world-model'
    const catalogData = Object.assign({}, mockModel, {name: modelName})
    const modelState = mockModelState({messages: [], catalogData})
    getSideModel.mockImplementation(() => ({success: true}))

    const {container, user} = render(
      <Toolbar
        onComparisonMode={false}
        option={PlaygroundContentOption.CHAT}
        position={Panel.Main}
        modelState={modelState}
        stopStreamingMessages={stopStreamingMessages}
      >
        foo toolbar content
      </Toolbar>,
      {playgroundState: mockPlaygroundState({models: [modelState]}), search: '?preset=foo&p=bar&other=baz'},
    )

    const resetHistoryButton = within(container).getByRole('button', {name: 'Reset chat history', hidden: true})
    expect(resetHistoryButton).toBeInTheDocument()
    expect(resetHistoryButton).toBeDisabled()
    expect(within(container).queryByTestId('restore-history-button')).not.toBeInTheDocument()
    expect(within(container).queryByText('foo toolbar content')).not.toBeInTheDocument()
    const addModelButton = within(container).getByRole('button', {name: 'Compare', hidden: true})
    expect(addModelButton).toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(setSyncInputs).not.toHaveBeenCalled()
    expect(getSideModel).not.toHaveBeenCalled()

    await user.click(addModelButton)

    expect(setSyncInputs).toHaveBeenCalledTimes(1)
    expect(setSyncInputs).toHaveBeenCalledWith(true)
    expect(getSideModel).toHaveBeenCalledTimes(1)
    expect(getSideModel).toHaveBeenCalledWith(modelName, modelState, true)
    expect(resetHistory).not.toHaveBeenCalled()
    expect(setMessages).not.toHaveBeenCalled()
    expect(RouteContext.location?.search).toBe(`?compare_to=${modelName}`)
  })

  test('renders Code option', () => {
    const selectedLanguage = 'ruby'
    const gettingStarted = Object.assign({}, mockGettingStarted)
    const languageName = 'Ruby'
    const sdkName = 'My Ruby SDK'
    gettingStarted[selectedLanguage] = {
      name: languageName,
      sdks: {'my-ruby-sdk': mockSDK({name: sdkName})},
    }
    const modelState = mockModelState({gettingStarted})
    const playgroundState = mockPlaygroundState({selectedLanguage})

    const {container} = render(
      <Toolbar
        onComparisonMode={false}
        option={PlaygroundContentOption.CODE}
        position={Panel.Main}
        modelState={modelState}
        stopStreamingMessages={stopStreamingMessages}
      >
        foo toolbar content
      </Toolbar>,
      {playgroundState},
    )

    expect(within(container).getByTestId('playground-language-button')).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: languageName})).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: sdkName})).toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Compare', hidden: true})).not.toBeInTheDocument()
    expect(within(container).queryByTestId('restore-history-button')).not.toBeInTheDocument()
    expect(within(container).queryByText('foo toolbar content')).not.toBeInTheDocument()
    expect(resetHistory).not.toHaveBeenCalled()
    expect(setMessages).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
    expect(getSideModel).not.toHaveBeenCalled()
  })

  test('renders JSON option when history cannot be restored', () => {
    const modelState = mockModelState()

    const {container} = render(
      <Toolbar
        onComparisonMode={false}
        option={PlaygroundContentOption.JSON}
        position={Panel.Main}
        modelState={modelState}
        stopStreamingMessages={stopStreamingMessages}
      >
        foo toolbar content
      </Toolbar>,
      {initialHistory: []},
    )

    expect(within(container).queryByTestId('restore-history-button')).not.toBeInTheDocument()
    expect(within(container).getByText('foo toolbar content')).toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Compare', hidden: true})).not.toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(resetHistory).not.toHaveBeenCalled()
    expect(setMessages).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
    expect(getSideModel).not.toHaveBeenCalled()
  })

  test('renders JSON option when history can be restored', () => {
    const modelState = mockModelState({messages: []})

    const {container} = render(
      <Toolbar
        onComparisonMode={false}
        option={PlaygroundContentOption.JSON}
        position={Panel.Main}
        modelState={modelState}
        stopStreamingMessages={stopStreamingMessages}
      >
        foo toolbar content
      </Toolbar>,
      {initialHistory: [mockStoredMessage], playgroundState: mockPlaygroundState({models: [modelState]})},
    )

    expect(within(container).getByTestId('restore-history-button')).toBeInTheDocument()
    expect(within(container).getByText('foo toolbar content')).toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Compare', hidden: true})).not.toBeInTheDocument()
    expect(within(container).queryByTestId('playground-language-button')).not.toBeInTheDocument()
    expect(resetHistory).not.toHaveBeenCalled()
    expect(setMessages).not.toHaveBeenCalled()
    expect(setSyncInputs).not.toHaveBeenCalled()
    expect(getSideModel).not.toHaveBeenCalled()
  })
})

interface renderOpts extends TestRenderOptions {
  initialHistory?: PlaygroundMessage[]
  playgroundState?: PlaygroundState
}

function render(component: JSX.Element, {initialHistory, playgroundState, ...rest}: renderOpts = {}) {
  const manager = {} as PlaygroundManager
  manager.resetHistory = resetHistory
  manager.setMessages = setMessages
  manager.setSyncInputs = setSyncInputs
  manager.getSideModel = getSideModel

  return htmlRender(component, {
    wrapper: ({children}) => (
      <PlaygroundManagerContext.Provider value={manager}>
        <PlaygroundStateProvider state={playgroundState ?? mockPlaygroundState()}>
          <MessageHistoryProvider initialHistory={initialHistory}>{children}</MessageHistoryProvider>
        </PlaygroundStateProvider>
      </PlaygroundManagerContext.Provider>
    ),
    ...rest,
  })
}
