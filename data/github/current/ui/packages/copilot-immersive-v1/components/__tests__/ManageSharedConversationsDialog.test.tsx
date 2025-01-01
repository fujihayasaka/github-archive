import {CopilotAuthTokenProvider} from '@github-ui/copilot-auth-token'
import {AuthToken} from '@github-ui/copilot-auth-token/auth-token'
import {getCopilotChatProviderProps} from '@github-ui/copilot-chat/test-utils/mock-data'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor, within} from '@testing-library/react'
import {http, HttpResponse} from 'msw'
import {setupServer} from 'msw/node'

import {ManageSharedConversationsDialog} from '../ManageSharedConversationsDialog'

const mockCloseDialog = jest.fn()

const mockThreads = [
  {
    id: '1',
    name: 'Test Conversation 1',
    updatedAt: '2024-03-24T10:00:00Z',
    sharedID: 'shared1',
  },
  {
    id: '2',
    name: 'Test Conversation 2',
    updatedAt: '2024-03-24T11:00:00Z',
    sharedID: 'shared2',
  },
  {
    id: '3',
    name: 'Test Conversation 3',
    updatedAt: '2024-03-24T12:00:00Z',
    sharedID: 'shared3',
  },
  {
    id: '4',
    name: 'Test Conversation 4',
    updatedAt: '2024-03-24T13:00:00Z',
    sharedID: 'shared4',
  },
  {
    id: '5',
    name: 'Test Conversation 5',
    updatedAt: '2024-03-24T14:00:00Z',
    sharedID: 'shared5',
  },
  {
    id: '6',
    name: 'Test Conversation 6',
    updatedAt: '2024-03-24T14:00:00Z',
    sharedID: 'shared6',
  },
]

const handlers = [
  http.get('apiURL/github/chat/threads', () => {
    return HttpResponse.json({threads: mockThreads})
  }),

  http.post('apiURL/github/chat/threads/unshare', () => {
    return HttpResponse.json({ok: true})
  }),

  http.post('/TEST_ANALYTICS_URL', () => {
    return HttpResponse.text('success')
  }),
]

const server = setupServer(...handlers)

describe('ManageSharedConversationsDialog', () => {
  beforeAll(() => {
    server.listen()
    // Store auth token in local storage
    const provider = new CopilotAuthTokenProvider([])
    provider.setLocalStorageAuthToken(new AuthToken('test-token', 'whenever', []))
  })

  afterEach(() => {
    server.resetHandlers()
    jest.clearAllMocks()
  })

  afterAll(() => server.close())

  const renderDialog = () => {
    return render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ManageSharedConversationsDialog closeDialog={mockCloseDialog} />
      </CopilotChatProvider>,
    )
  }

  it('shows loading state initially', () => {
    renderDialog()
    expect(screen.getByText('Loading shared conversations')).toBeInTheDocument()
    expect(screen.getByText('Your shared conversations will appear here.')).toBeInTheDocument()
  })

  it('shows empty state when no shared threads exist', async () => {
    server.use(
      http.get('apiURL/github/chat/threads', () => {
        return HttpResponse.json({threads: []})
      }),
    )
    renderDialog()

    await waitFor(() => {
      expect(screen.getByText('No shared conversations')).toBeInTheDocument()
    })
    const emptyIcon = screen.getByLabelText('No shared conversations')
    expect(emptyIcon).toBeInTheDocument()
    expect(screen.getByText('Your shared conversations will appear here.')).toBeInTheDocument()
  })

  it('shows error blankslate with correct messaging', async () => {
    server.use(
      http.get('apiURL/github/chat/threads', () => {
        return HttpResponse.error()
      }),
    )

    renderDialog()

    await screen.findByRole('heading', {
      name: "We couldn't load the shared conversations",
    })

    const errorIcon = screen.getByLabelText('Error loading shared conversations')
    expect(errorIcon).toBeInTheDocument()
    expect(errorIcon).toHaveClass('alertIcon') // Verify styling
    expect(screen.getByText('Try again or, if the problem persists, contact support.')).toBeInTheDocument()
  })

  it('displays shared threads in table', async () => {
    renderDialog()

    await waitFor(() => {
      expect(screen.getByText('Test Conversation 1')).toBeInTheDocument()
    })
    expect(screen.getByText('Test Conversation 2')).toBeInTheDocument()
  })

  it('copies link from conversation row', async () => {
    const {user} = renderDialog()
    const mockWriteText = jest.fn().mockImplementation(() => Promise.resolve())
    Object.defineProperty(navigator, 'clipboard', {
      value: {writeText: mockWriteText},
      configurable: true,
    })

    const firstRow = await screen.findByRole('row', {
      name: /Test Conversation 1/,
    })

    // Find copy button within the first row
    const copyButton = within(firstRow).getByRole('button', {
      name: 'Copy share link',
    })

    await user.click(copyButton)

    // Verify the correct URL was copied
    expect(mockWriteText).toHaveBeenCalledWith(`${window.location.origin}/copilot/share/shared1`)
  })

  it('displays confirmation text when unshare all conversations button is clicked', async () => {
    const {user} = renderDialog()

    // Wait for the first conversation to appear
    await screen.findByRole('row', {
      name: /Test Conversation 1/,
    })

    const unshareButton = screen.getByRole('button', {name: 'Unshare all'})
    await user.click(unshareButton)

    const confirmationText = screen.getByText('Are you sure you want to unshare all 6 conversations?')
    expect(confirmationText).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Unshare all'})).toBeInTheDocument()
  })

  it('unshares all conversations when confirmation button is clicked', async () => {
    const {user} = renderDialog()

    // Wait for the first conversation to appear
    await screen.findByRole('row', {
      name: /Test Conversation 1/,
    })

    let unshareButton = screen.getByRole('button', {name: 'Unshare all'})
    // Clicking once displays the text
    await user.click(unshareButton)
    // Wait for the confirmation text to appear
    await screen.findByText('Are you sure you want to unshare all 6 conversations?')
    // Get the confirmation button again
    unshareButton = screen.getByRole('button', {name: 'Unshare all'})
    // Clicking again unshares the conversations and closes dialog
    await user.click(unshareButton)

    await waitFor(() => {
      expect(screen.getByText('No shared conversations')).toBeInTheDocument()
    })
    const emptyIcon = screen.getByLabelText('No shared conversations')
    expect(emptyIcon).toBeInTheDocument()
  })

  it('closes dialog when close button clicked', async () => {
    const {user} = renderDialog()
    const closeButton = screen.getByRole('button', {name: 'Close'})
    await user.click(closeButton)
    expect(mockCloseDialog).toHaveBeenCalled()
  })

  it('displays correct number of items per page', async () => {
    renderDialog()

    await screen.findByText('Test Conversation 1')

    // Page should show first 5 items
    expect(screen.getByText('Test Conversation 1')).toBeInTheDocument()
    expect(screen.getByText('Test Conversation 2')).toBeInTheDocument()
    expect(screen.getByText('Test Conversation 3')).toBeInTheDocument()
    expect(screen.getByText('Test Conversation 4')).toBeInTheDocument()
    expect(screen.getByText('Test Conversation 5')).toBeInTheDocument()
    expect(screen.queryByText('Test Conversation 6')).not.toBeInTheDocument()
  })
})
