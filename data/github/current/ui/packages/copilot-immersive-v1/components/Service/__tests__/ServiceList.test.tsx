import {getCopilotChatProviderProps} from '@github-ui/copilot-chat/test-utils/mock-data'
import {copilotFeatureFlags} from '@github-ui/copilot-chat/utils/copilot-feature-flags'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render} from '@github-ui/react-core/test-utils'
import {fireEvent, screen} from '@testing-library/react'

import {ServiceList} from '../ServiceList'

const mockNavigateToNewThread = jest.fn()
jest.mock('../../../hooks/use-navigate-to-new-thread', () => ({
  // eslint-disable-next-line @eslint-react/hooks-extra/no-useless-custom-hooks
  useNavigateToNewThread: () => mockNavigateToNewThread,
}))

const mockSelectPlugin = jest.fn()
const mockDispatch = jest.fn()
jest.mock('@github-ui/copilot-chat/CopilotChatManagerContext', () => {
  return {
    ...jest.requireActual('@github-ui/copilot-chat/CopilotChatManagerContext'),
    // eslint-disable-next-line @eslint-react/hooks-extra/no-useless-custom-hooks
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
    // eslint-disable-next-line @eslint-react/hooks-extra/no-useless-custom-hooks
    usePlugins: () => mockPlugins,
  }
})

describe('ServiceList', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('renders the dashboard navigation item', () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} threadId={null} mode="immersive">
        <ServiceList />
      </CopilotChatProvider>,
    )

    expect(screen.getByRole('link', {name: /Dashboard/i})).toBeInTheDocument()
    expect(screen.getByRole('link', {name: /Dashboard/i})).toHaveAttribute('aria-current', 'page')
  })

  it('does not render spaces navigation when customCopilots flag is disabled', () => {
    jest.spyOn(copilotFeatureFlags, 'customCopilots', 'get').mockReturnValue(false)

    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ServiceList />
      </CopilotChatProvider>,
    )

    expect(screen.queryByTestId('spaces-navigation')).not.toBeInTheDocument()
  })

  it('renders spaces navigation when customCopilots flag is enabled', () => {
    jest.spyOn(copilotFeatureFlags, 'customCopilots', 'get').mockReturnValue(true)

    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ServiceList />
      </CopilotChatProvider>,
    )

    expect(screen.getByText('Spaces')).toBeInTheDocument()
  })

  it('renders plugin navigation components', () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ServiceList />
      </CopilotChatProvider>,
    )

    expect(screen.getByTestId('test-plugin-nav')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Test Plugin'})).toBeInTheDocument()
  })

  it('handles dashboard navigation click correctly', async () => {
    const {user} = render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ServiceList />
      </CopilotChatProvider>,
    )

    const dashboardLink = screen.getByRole('link', {name: /Dashboard/i})
    await user.click(dashboardLink)

    expect(mockNavigateToNewThread).toHaveBeenCalledWith({clearTopic: true, includeThreads: false})
    expect(mockSendEvent).toHaveBeenCalledWith('dotcom_chat.activate', {
      target: 'SIDEBAR_CONVERSATION_NEW',
      mode: 'immersive',
    })
  })

  it('does not trigger navigation when ctrl/cmd+click is used on dashboard link', () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ServiceList />
      </CopilotChatProvider>,
    )

    const dashboardLink = screen.getByRole('link', {name: /Dashboard/i})

    // Test with metaKey
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(dashboardLink, {metaKey: true})
    expect(mockSelectPlugin).not.toHaveBeenCalled()
    expect(mockNavigateToNewThread).not.toHaveBeenCalled()

    // Test with ctrlKey
    // eslint-disable-next-line testing-library/prefer-user-event
    fireEvent.click(dashboardLink, {ctrlKey: true})
    expect(mockSelectPlugin).not.toHaveBeenCalled()
    expect(mockNavigateToNewThread).not.toHaveBeenCalled()
  })

  it('handles plugin navigation click correctly', async () => {
    const {user} = render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} mode="immersive">
        <ServiceList />
      </CopilotChatProvider>,
    )

    const pluginButton = screen.getByRole('button', {name: 'Test Plugin'})
    await user.click(pluginButton)

    expect(mockDispatch).toHaveBeenCalledWith({type: 'SET_CUSTOM_COPILOT_ID', customCopilotId: null})
    expect(mockSelectPlugin).toHaveBeenCalledWith('test-plugin')
  })

  it('does not set aria-current when not on main page', () => {
    render(
      <CopilotChatProvider {...getCopilotChatProviderProps()} threadId="test-id" mode="immersive">
        <ServiceList />
      </CopilotChatProvider>,
    )

    const dashboardLink = screen.getByRole('link', {name: /Dashboard/i})
    expect(dashboardLink).not.toHaveAttribute('aria-current', 'page')
  })
})
