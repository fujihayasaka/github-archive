import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {AuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import {CopilotChatManager} from '@github-ui/copilot-chat/utils/copilot-chat-manager'
import type {CopilotChatMessage, CopilotChatThread} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {http, HttpResponse} from 'msw'
import {setupServer} from 'msw/node'

import {ContentPreviewProvider} from '../ContentPreview/ContentPreviewContext'
import {ConversationSharingDialog} from '../ConversationSharingDialog'

const mockCloseDialog = jest.fn()

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

function UnshareConversationSetup({threads = defaultThreads}) {
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
        <ConversationSharingDialog closeDialog={mockCloseDialog} threadId="123" />
      </ContentPreviewProvider>
    </CopilotChatProvider>
  )
}

const handlers = [
  http.patch('apiURL/github/chat/threads/2/share', async ({request}) => {
    const requestBody = await request.json()
    // CAPI request expects snake case
    // eslint-disable-next-line camelcase
    const {shared_message_id} = requestBody as {shared_message_id: string}
    // eslint-disable-next-line camelcase
    if (shared_message_id !== '') {
      return HttpResponse.json({
        thread: {
          sharedID: 'shared-thread-id-for-active-subthread',
          sharedAt: '2025-03-23T23:23:23Z',
          sharedMessageID: 'active-subthread-message-id',
        } as CopilotChatThread,
      })
    }

    return HttpResponse.json({
      thread: {
        sharedID: 'shared-thread-id-for-thread-with-most-recent-message',
        sharedAt: '2025-03-23T23:23:23Z',
        sharedMessageID: '',
      } as CopilotChatThread,
    })
  }),

  http.post('/TEST_ANALYTICS_URL', () => {
    return HttpResponse.text('success')
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

  const renderDialog = () => {
    return render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ConversationSharingDialog closeDialog={mockCloseDialog} threadId="2" />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )
  }

  test('has share button when conversation has never been shared', () => {
    renderDialog()

    expect(screen.getByRole('dialog', {name: 'Share conversation'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: 'Share conversation'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Close'})).toBeInTheDocument()

    expect(
      screen.getByText(
        'When shared, this conversation and future messages will be visible to anyone with the link. If private repository content is included, repository access is required to view.',
      ),
    ).toBeInTheDocument()

    expect(screen.getByRole('textbox', {name: 'Shared link'})).toHaveValue('')
    expect(screen.getByRole('button', {name: 'Share'})).toBeInTheDocument()

    expect(screen.queryByRole('button', {name: 'Unshare'})).not.toBeInTheDocument()
  })

  test('displays a shared link when share button is clicked', async () => {
    jest.spyOn(copilotFeatureFlags, 'copilotShareActiveSubthread', 'get').mockReturnValue(false)

    const {user} = renderDialog()

    const createLinkButton = screen.getByRole('button', {name: 'Share'})
    await user.click(createLinkButton)

    expect(
      screen.getByText(
        'This conversation and future messages are visible to anyone with the link. If private repository content is included, repository access is required to view.',
      ),
    ).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Copy link'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Unshare'})).toBeInTheDocument()
    expect(screen.getByRole('textbox', {name: 'Shared link'})).toHaveValue(
      'http://localhost/copilot/share/shared-thread-id-for-thread-with-most-recent-message',
    )
    expect(screen.getByRole('heading', {name: 'Conversation shared'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Share'})).not.toBeInTheDocument()
  })

  test('shares the active subthread when the feature flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'copilotShareActiveSubthread', 'get').mockReturnValue(true)

    const {user} = renderDialog()

    const createLinkButton = screen.getByRole('button', {name: 'Share'})
    await user.click(createLinkButton)

    expect(screen.getByText('This shared conversation is a snapshot')).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Copy link'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Unshare'})).toBeInTheDocument()
    expect(screen.getByRole('textbox', {name: 'Shared link'})).toHaveValue(
      'http://localhost/copilot/share/shared-thread-id-for-active-subthread',
    )
    expect(screen.getByRole('heading', {name: 'Conversation shared'})).toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Share'})).not.toBeInTheDocument()
  })

  test('shows "Conversation shared" when share button is clicked', async () => {
    const {user} = renderDialog()
    const createLinkButton = screen.getByRole('button', {name: 'Share'})
    await user.click(createLinkButton)

    expect(screen.getByRole('heading', {name: 'Conversation shared'})).toBeInTheDocument()
    expect(screen.getByRole('dialog', {name: 'Conversation shared'})).toBeInTheDocument()
  })

  test('shows "Visible to anyone with the link" when conversation has been shared', () => {
    render(<UnshareConversationSetup />)

    expect(screen.getByText('Visible to anyone with the link')).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: 'Conversation shared'})).toBeInTheDocument()
  })

  test('shows "Unshare" button when conversation has been shared', () => {
    render(<UnshareConversationSetup />)

    expect(screen.getByRole('button', {name: 'Unshare'})).toBeInTheDocument()
  })

  test('shows confirmation text when unshare button is clicked', async () => {
    const {user} = render(<UnshareConversationSetup />)

    const unshareButton = screen.getByRole('button', {name: 'Unshare'})
    await user.click(unshareButton)

    expect(screen.getByText('Confirm unsharing this conversation?')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Unshare'})).toBeInTheDocument()
  })
})
