import {getCopilotChatProviderProps} from '@github-ui/copilot-chat/test-utils/mock-data'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render} from '@github-ui/react-core/test-utils'
import {fireEvent, screen} from '@testing-library/react'

import {ServiceList} from '../ServiceList'

const mockNavigateToNewThread = jest.fn()
jest.mock('../../../hooks/use-navigate-to-new-thread', () => ({
  useNavigateToNewThread: () => mockNavigateToNewThread,
}))

const mockSelectPlugin = jest.fn()
const mockDispatch = jest.fn()
jest.mock('@github-ui/copilot-chat/CopilotChatManagerContext', () => {
  return {
    ...jest.requireActual('@github-ui/copilot-chat/CopilotChatManagerContext'),
    useChatManager: () => {
      return {
        selectPlugin: mockSelectPlugin,
        dispatch: mockDispatch,
      }
    },
  }
})

const mockSendEvent = jest.fn()
jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: (...args: unknown[]) => mockSendEvent(...args),
  }
})

const mockPlugins = [
  {
    id: 'test-plugin',
    name: 'Test Plugin',
    navigationDisplayName: 'Test Plugin Navigation',
    NavigationComponent: ({
      onLinkClick,
    }: {
      onLinkClick: (e: React.MouseEvent<HTMLButtonElement>, id: string) => void
    }) => (
      <li data-testid="test-plugin-nav">
        <button onClick={e => onLinkClick(e, 'test-plugin')}>Test Plugin</button>
      </li>
    ),
  },
]

jest.mock('@github-ui/copilot-chat/plugin/registry', () => {
  return {
    usePlugins: () => mockPlugins,
  }
})

describe('ServiceList', () => {
  const mockToggleFloatingSidebar = jest.fn()

  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('renders the dashboard navigation item', () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} threadId={null} mode="immersive">
        <ServiceList toggleFloatingSidebar={mockToggleFloatingSidebar} />
      </CopilotChatProvider>,
    )

    expect(screen.getByRole('link', {name: /Home/i})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: /Home/i})).toHaveAttribute('aria-current', 'page')
  })

  it('does not render spaces navigation when customCopilots flag is disabled', () => {
    jest.spyOn(copilotFeatureFlags, 'customCopilots', 'get').mockReturnValue(false)

    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ServiceList toggleFloatingSidebar={mockToggleFloatingSidebar} />
      </CopilotChatProvider>,
    )

    expect(screen.queryByTestId('spaces-navigation')).not.toBeInTheDocument()
  })

  test('renders spaces navigation when customCopilotsEnabled is set to true in the chatProviderProps', () => {
    const chatProviderProps = getCopilotChatProviderProps()
    chatProviderProps.copilotChatPayload.customCopilotsEnabled = true

    render(
      <CopilotChatProvider {...chatProviderProps} mode="immersive">
        <ServiceList toggleFloatingSidebar={mockToggleFloatingSidebar} />
      </CopilotChatProvider>,
    )

    expect(screen.getByText('Spaces')).toBeInTheDocument()
  })

  test('does not render spaces navigation when customCopilotsEnabled is set to false in the chatProviderProps', () => {
    const chatProviderProps = getCopilotChatProviderProps()
    chatProviderProps.copilotChatPayload.customCopilotsEnabled = false

    render(
      <CopilotChatProvider {...chatProviderProps} mode="immersive">
        <ServiceList toggleFloatingSidebar={mockToggleFloatingSidebar} />
      </CopilotChatProvider>,
    )

    expect(screen.queryByText('Spaces')).not.toBeInTheDocument()
  })

  it('renders plugin navigation components', () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ServiceList toggleFloatingSidebar={mockToggleFloatingSidebar} />
      </CopilotChatProvider>,
    )

    expect(screen.getByTestId('test-plugin-nav')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Test Plugin'})).toBeInTheDocument()
  })

  it('handles dashboard navigation click correctly and calls toggleFloatingSidebar', async () => {
    const {user} = render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ServiceList toggleFloatingSidebar={mockToggleFloatingSidebar} />
      </CopilotChatProvider>,
    )

    const dashboardLink = screen.getByRole('link', {name: /Home/i})
    await user.click(dashboardLink)

    expect(mockToggleFloatingSidebar).toHaveBeenCalled()
    expect(mockNavigateToNewThread).toHaveBeenCalledWith({clearTopic: true, includeThreads: false})
    expect(mockSendEvent).toHaveBeenCalledWith('dotcom_chat.activate', {
      target: 'SIDEBAR_CONVERSATION_NEW',
      mode: 'immersive',
    })
  })

  it('does not trigger navigation when ctrl/cmd+click is used on dashboard link', () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ServiceList toggleFloatingSidebar={mockToggleFloatingSidebar} />
      </CopilotChatProvider>,
    )

    const dashboardLink = screen.getByRole('link', {name: /Home/i})

    // Test with metaKey
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(dashboardLink, {metaKey: true})
    expect(mockToggleFloatingSidebar).not.toHaveBeenCalled() // Ensure toggle is NOT called
    expect(mockSelectPlugin).not.toHaveBeenCalled()
    expect(mockNavigateToNewThread).not.toHaveBeenCalled()

    // Test with ctrlKey
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(dashboardLink, {ctrlKey: true})
    expect(mockToggleFloatingSidebar).not.toHaveBeenCalled()
    expect(mockSelectPlugin).not.toHaveBeenCalled()
    expect(mockNavigateToNewThread).not.toHaveBeenCalled()
  })

  it('handles plugin navigation click correctly and calls toggleFloatingSidebar', async () => {
    const {user} = render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ServiceList toggleFloatingSidebar={mockToggleFloatingSidebar} />
      </CopilotChatProvider>,
    )

    const pluginButton = screen.getByRole('button', {name: 'Test Plugin'})
    await user.click(pluginButton)

    expect(mockToggleFloatingSidebar).toHaveBeenCalled() // Ensure sidebar toggle is called
    expect(mockSelectPlugin).toHaveBeenCalledWith('test-plugin')
  })

  it('does not set aria-current when not on main page', () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} threadId="test-id" mode="immersive">
        <ServiceList toggleFloatingSidebar={mockToggleFloatingSidebar} />
      </CopilotChatProvider>,
    )

    const dashboardLink = screen.getByRole('link', {name: /Home/i})
    expect(dashboardLink).not.toHaveAttribute('aria-current', 'page')
  })
})
