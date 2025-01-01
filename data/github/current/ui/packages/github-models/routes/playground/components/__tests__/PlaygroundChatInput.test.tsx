import {within} from '@testing-library/react'
import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {PlaygroundChatInput} from '../PlaygroundChatInput'
import {mockModelState, mockPlaygroundState} from './mocks'
import {Panel, type PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import {AttachmentsProvider} from '@github-ui/attachments'
import type {ModelState, PlaygroundState} from '../../../../types'
import {mockShowModelPayload} from '../../../show/components/__tests__/mocks'
import {mockModel} from '../../__tests__/mocks'

const stopStreamingMessages = jest.fn().mockName('stopStreamingMessages')
const sendMessage = jest.fn().mockName('sendMessage')
const setChatInput = jest.fn().mockName('setChatInput')

describe('PlaygroundChatInput', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders when model has finished loading', async () => {
    const chatInput = 'Hello write me a poem please'
    const position = Panel.Main
    const modelState = mockModelState({chatInput, isLoading: false})
    const models: ModelState[] = []
    models[position] = modelState
    const playgroundState = mockPlaygroundState({models})

    const {container, user} = render(
      <PlaygroundChatInput
        model={modelState}
        position={position}
        stopStreamingMessages={stopStreamingMessages}
        sendMessage={sendMessage}
      />,
      {playgroundState},
    )

    const promptTextarea = within(container).getByRole('textbox', {name: 'Prompt'})
    expect(promptTextarea).toHaveValue(chatInput)
    expect(promptTextarea).toBeEnabled()
    expect(within(container).getByRole('button', {name: 'Send now'})).toBeEnabled()
    expect(within(container).getByRole('tooltip', {name: 'Send now'})).toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Stop'})).not.toBeInTheDocument()
    expect(within(container).queryByRole('tooltip', {name: 'Stop'})).not.toBeInTheDocument()
    expect(setChatInput).not.toHaveBeenCalled()

    const newKeystrokes = ', ty'
    await user.type(promptTextarea, newKeystrokes)

    expect(setChatInput).toHaveBeenCalledTimes(newKeystrokes.length)
    expect(stopStreamingMessages).not.toHaveBeenCalled()
    expect(sendMessage).not.toHaveBeenCalled()
  })

  test('allows submitting form', async () => {
    const chatInput = 'Hello write me a poem please'
    const position = Panel.Main
    const modelState = mockModelState({chatInput, isLoading: false})
    const models: ModelState[] = []
    models[position] = modelState
    const playgroundState = mockPlaygroundState({models})

    const {container, user} = render(
      <PlaygroundChatInput
        model={modelState}
        position={position}
        stopStreamingMessages={stopStreamingMessages}
        sendMessage={sendMessage}
      />,
      {playgroundState},
    )

    const submitButton = within(container).getByRole('button', {name: 'Send now'})
    expect(submitButton).toBeInTheDocument()
    expect(submitButton).toBeEnabled()
    expect(sendMessage).not.toHaveBeenCalled()
    expect(setChatInput).not.toHaveBeenCalled()

    await user.click(submitButton)

    expect(sendMessage).toHaveBeenCalledTimes(1)
    expect(sendMessage).toHaveBeenCalledWith(chatInput, [])
    expect(stopStreamingMessages).not.toHaveBeenCalled()
    expect(setChatInput).toHaveBeenCalledTimes(1)
    expect(setChatInput).toHaveBeenCalledWith(position, '')
  })

  test('renders when a model is still loading', async () => {
    const modelState = mockModelState({isLoading: true})
    const playgroundState = mockPlaygroundState({models: [modelState]})

    const {container, user} = render(
      <PlaygroundChatInput
        model={modelState}
        position={Panel.Main}
        stopStreamingMessages={stopStreamingMessages}
        sendMessage={sendMessage}
      />,
      {playgroundState},
    )

    const stopButton = within(container).getByRole('button', {name: 'Stop'})
    expect(stopButton).toBeInTheDocument()
    expect(stopButton).toBeEnabled()
    expect(within(container).getByRole('tooltip', {name: 'Stop'})).toBeInTheDocument()
    expect(within(container).queryByRole('button', {name: 'Send now'})).not.toBeInTheDocument()
    expect(within(container).queryByRole('tooltip', {name: 'Send now'})).not.toBeInTheDocument()

    await user.click(stopButton)

    expect(stopStreamingMessages).toHaveBeenCalledTimes(1)
    expect(sendMessage).not.toHaveBeenCalled()
    expect(setChatInput).not.toHaveBeenCalled()
  })

  test('renders when chat is closed for a model', () => {
    const modelState = mockModelState({isLoading: false, chatClosed: true})
    const playgroundState = mockPlaygroundState({models: [modelState]})

    const {container} = render(
      <PlaygroundChatInput
        model={modelState}
        position={Panel.Main}
        stopStreamingMessages={stopStreamingMessages}
        sendMessage={sendMessage}
      />,
      {playgroundState},
    )

    expect(within(container).getByRole('textbox', {name: 'Prompt'})).toBeDisabled()
    expect(within(container).getByRole('button', {name: 'Send now'})).toBeDisabled()
    expect(within(container).queryByRole('button', {name: 'Stop'})).not.toBeInTheDocument()
    expect(setChatInput).not.toHaveBeenCalled()
    expect(stopStreamingMessages).not.toHaveBeenCalled()
    expect(sendMessage).not.toHaveBeenCalled()
  })

  test('renders the improve user prompt icon', () => {
    const modelState = mockModelState()
    const playgroundState = mockPlaygroundState({models: [modelState]})

    const {container} = render(
      <PlaygroundChatInput
        model={modelState}
        position={Panel.Main}
        stopStreamingMessages={stopStreamingMessages}
        sendMessage={sendMessage}
      />,
      {
        playgroundState,
        routePayload: mockShowModelPayload({improvedPromptModel: mockModel}),
      },
    )

    expect(within(container).getByLabelText('Open improve prompt dialog')).toBeInTheDocument()
  })
})

function render(
  component: JSX.Element,
  {playgroundState, ...opts}: TestRenderOptions & {playgroundState?: PlaygroundState} = {},
) {
  const manager = {} as PlaygroundManager
  manager.setChatInput = setChatInput

  return htmlRender(
    <PlaygroundManagerProvider manager={manager}>
      <PlaygroundStateProvider state={playgroundState ?? mockPlaygroundState()}>
        <AttachmentsProvider>{component}</AttachmentsProvider>
      </PlaygroundStateProvider>
    </PlaygroundManagerProvider>,
    opts,
  )
}
