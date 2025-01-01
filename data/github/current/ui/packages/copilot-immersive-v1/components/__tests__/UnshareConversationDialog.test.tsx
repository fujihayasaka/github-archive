import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {AuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import {CopilotChatManager} from '@github-ui/copilot-chat/utils/copilot-chat-manager'
import type {CopilotChatMessage, CopilotChatThread} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {http, HttpResponse} from 'msw'
import {setupServer} from 'msw/node'

import {ContentPreviewProvider} from '../ContentPreview/ContentPreviewContext'
import {UnshareConversationDialog} from '../UnshareConversationDialog'

const mockCloseDialog = jest.fn()

const userEvent = setupUserEvent()

const defaultThreads = new Map([
  [
    '123',
    {
      id: '123',
      sharedID: 'shared-123',
      name: 'Test Thread',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    },
  ],
])

const message = {
  id: 'message-123',
  role: 'user',
  createdAt: new Date().toISOString(),
  threadID: '123',
  references: [],
  content: 'Test message content',
} as CopilotChatMessage

function UnshareConversationDialogSetup({threads = defaultThreads}) {
  return (
    <CopilotChatProvider
      {...getCopilotChatProviderProps()}
      topic={undefined}
      threadId="123"
      mode="immersive"
      testReducerState={{
        ...getDefaultReducerState('123', undefined, 'immersive'),
        messagesLoading: {state: 'loaded' as const, error: null},
        threads,
        selectedThreadID: '123',
        messages: [message],
      }}
    >
      <ContentPreviewProvider>
        <UnshareConversationDialog closeDialog={mockCloseDialog} threadId="123" />
      </ContentPreviewProvider>
    </CopilotChatProvider>
  )
}

const handlers = [
  http.patch('apiURL/github/chat/threads/123/unshare', () => {
    return HttpResponse.json({
      thread: {
        sharedID: '',
        sharedAt: '',
        sharedMessageID: '',
      } as CopilotChatThread,
    })
  }),

  http.post('/TEST_ANALYTICS_URL', async ({request}) => {
    const requestBody = await request.json()
    const {type} = requestBody as {type: string}
    const {context} = requestBody as {context: {target: string}}
    if (type === 'copilot.shared_thread_update') {
      return HttpResponse.text('success')
    } else if (type === 'dotcom_chat.activate') {
      if (context.target === 'COPILOT_UNSHARE_SHARED_CONVERSATION') {
        return HttpResponse.text('success')
      }
    }
  }),
]

const server = setupServer(...handlers)
beforeAll(() => server.listen())
afterEach(() => server.resetHandlers())
afterAll(() => server.close())

describe('ConversationSharingDialog', () => {
  beforeEach(() => {
    // Store auth token in local storage so that client doesn't try to fetch it
    const provider = new CopilotAuthTokenProvider([])
    provider.setLocalStorageAuthToken(new AuthToken('buttercakes', 'whenever', []))

    jest.spyOn(CopilotChatManager.prototype, 'FindLastMessageID').mockReturnValue('active-subthread-last-message-id')
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders dialog with thread information', () => {
    render(<UnshareConversationDialogSetup />)

    expect(screen.getByRole('dialog', {name: 'Unshare conversation'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: 'Unshare conversation'})).toBeInTheDocument()

    expect(screen.getByText('Test Thread')).toBeInTheDocument()
    expect(screen.getByText('Test message content')).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Unshare'})).toBeInTheDocument()
  })

  it('closes dialog when cancel is clicked', async () => {
    render(<UnshareConversationDialogSetup />)

    const cancelButton = screen.getByRole('button', {name: 'Cancel'})
    await userEvent.click(cancelButton)

    expect(mockCloseDialog).toHaveBeenCalled()
  })

  it('calls unshareThread and closes the dialog when unshare button is clicked', async () => {
    render(<UnshareConversationDialogSetup />)

    const unshareButton = screen.getByRole('button', {name: 'Unshare'})
    await userEvent.click(unshareButton)
    expect(mockCloseDialog).toHaveBeenCalled()
  })
})
