import {act, within} from '@testing-library/react'
import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {PlaygroundJSON} from '../PlaygroundJSON'
import {mockModelState} from './mocks'
import {Panel} from '../../../../utils/playground-manager'
import {AttachmentsProvider} from '@github-ui/attachments'
import {PlaygroundManagerProvider} from '../../../../contexts/PlaygroundManagerContext'
import type {PlaygroundManager} from '../../../../utils/playground-manager'

const setToolbarContent = jest.fn().mockName('setToolbarContent')
const setFullWidthToolbarContent = jest.fn().mockName('setFullWidthToolbarContent')
const stopStreamingMessages = jest.fn().mockName('stopStreamingMessages')
const sendMessage = jest.fn().mockName('sendMessage')
const setMessages = jest.fn().mockName('setMessages')

describe('PlaygroundJSON', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders', async () => {
    const modelState = mockModelState()
    const position = Panel.Main

    const {container, user} = await render(
      <PlaygroundJSON
        model={modelState}
        position={position}
        setToolbarContent={setToolbarContent}
        setFullWidthToolbarContent={setFullWidthToolbarContent}
        stopStreamingMessages={stopStreamingMessages}
        sendMessage={sendMessage}
      />,
    )

    const codeMirrorEditorEl = within(container).getByTestId('codemirror-editor')
    expect(codeMirrorEditorEl).toBeInTheDocument()
    expect(within(codeMirrorEditorEl).getByRole('textbox', {name: 'JSON'})).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Copy to clipboard'})).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Share feedback'})).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Product Terms'})).toBeInTheDocument()
    expect(within(container).getByRole('link', {name: 'Privacy Statement'})).toBeInTheDocument()
    expect(within(container).getByRole('textbox', {name: 'Prompt'})).toBeInTheDocument()
    const sendButton = within(container).getByRole('button', {name: 'Send now'})
    expect(sendButton).toBeEnabled()
    expect(setToolbarContent).toHaveBeenCalledTimes(1)
    expect(setFullWidthToolbarContent).toHaveBeenCalledTimes(1)
    expect(setFullWidthToolbarContent).toHaveBeenCalledWith(null)
    expect(sendMessage).not.toHaveBeenCalled()

    await user.click(sendButton)

    expect(sendMessage).toHaveBeenCalledTimes(1)
    expect(stopStreamingMessages).not.toHaveBeenCalled()
    expect(setMessages).not.toHaveBeenCalled()
  })
})

async function render(component: JSX.Element) {
  const manager = {} as PlaygroundManager
  manager.setMessages = setMessages

  // Need the `act` call to avoid a warning about "A suspended resource finished loading inside a test, but the
  // event was not wrapped in act" due to `Suspense` being used in PlaygroundJSON.
  // eslint-disable-next-line testing-library/no-unnecessary-act
  return await act(() => {
    return htmlRender(component, {
      wrapper: ({children}) => (
        <PlaygroundManagerProvider manager={manager}>
          <AttachmentsProvider>{children}</AttachmentsProvider>
        </PlaygroundManagerProvider>
      ),
    })
  })
}
