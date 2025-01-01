import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {AuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {getCopilotChatProviderProps} from '@github-ui/copilot-chat/test-utils/mock-data'
import {CopilotChatManager} from '@github-ui/copilot-chat/utils/copilot-chat-manager'
import type {CopilotChatThread} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {http, HttpResponse} from 'msw'
import {setupServer} from 'msw/node'

import {ContentPreviewProvider} from '../ContentPreview/ContentPreviewContext'
import {ShareConversationDialog} from '../ShareConversationDialog'

const mockCloseDialog = jest.fn()

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
        sharedMessageID: 'latest-message-id',
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

describe('ShareConversationDialog', () => {
  beforeEach(() => {
    // Store auth token in local storage so that client doesn't try to fetch it
    const provider = new CopilotAuthTokenProvider([])
    provider.setLocalStorageAuthToken(new AuthToken('buttercakes', 'whenever', []))

    jest.spyOn(CopilotChatManager.prototype, 'FindLastMessageID').mockReturnValue('active-subthread-last-message-id')
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  test('has expected copy and buttons when conversation has never been shared', () => {
    jest.spyOn(copilotFeatureFlags, 'copilotShareActiveSubthread', 'get').mockReturnValue(false)

    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ShareConversationDialog closeDialog={mockCloseDialog} threadId="2" />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.getByRole('dialog', {name: 'Share conversation'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {name: 'Share conversation'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(screen.getByRole('region', {name: 'Private content banner'})).toBeInTheDocument()

    expect(
      screen.getByText(
        'This conversation may contain private content. Viewers must have access to all referenced content.',
      ),
    ).toBeInTheDocument()

    expect(screen.getByRole('textbox', {name: 'Shared link'})).toHaveValue('')
    expect(screen.getByRole('button', {name: 'Create link'})).toBeInTheDocument()
    expect(screen.getByText('create link to share the current version of this conversation.')).toBeInTheDocument()

    expect(screen.queryByRole('button', {name: 'Copy link'})).not.toBeInTheDocument()
    expect(screen.queryByRole('button', {name: 'Manage link'})).not.toBeInTheDocument()
  })

  test('displays a shared link when create link is clicked', async () => {
    jest.spyOn(copilotFeatureFlags, 'copilotShareActiveSubthread', 'get').mockReturnValue(false)

    const {user} = render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ShareConversationDialog closeDialog={mockCloseDialog} threadId="2" />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    const createLinkButton = screen.getByRole('button', {name: 'Create link'})
    await user.click(createLinkButton)

    expect(screen.getByRole('region', {name: 'Private content banner'})).toBeInTheDocument()
    expect(
      screen.getByText(
        'This conversation may contain private content. Viewers must have access to all referenced content.',
      ),
    ).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Copy link'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Manage link'})).toBeInTheDocument()
    expect(screen.getByRole('textbox', {name: 'Shared link'})).toHaveValue(
      'http://localhost/copilot/share/shared-thread-id-for-thread-with-most-recent-message',
    )
  })

  test('shares the active subthread when the feature flag is enabled', async () => {
    jest.spyOn(copilotFeatureFlags, 'copilotShareActiveSubthread', 'get').mockReturnValue(true)

    const {user} = render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} topic={undefined} threadId="2" mode="immersive">
        <ContentPreviewProvider>
          <ShareConversationDialog closeDialog={mockCloseDialog} threadId="2" />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    const createLinkButton = screen.getByRole('button', {name: 'Create link'})
    await user.click(createLinkButton)

    expect(
      screen.getByText(
        'This conversation may contain private content. Viewers must have access to all referenced content.',
      ),
    ).toBeInTheDocument()

    expect(screen.getByRole('button', {name: 'Copy link'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Manage link'})).toBeInTheDocument()
    expect(screen.getByRole('textbox', {name: 'Shared link'})).toHaveValue(
      'http://localhost/copilot/share/shared-thread-id-for-active-subthread',
    )
  })
})
