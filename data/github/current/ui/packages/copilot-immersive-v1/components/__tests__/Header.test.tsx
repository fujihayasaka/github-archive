import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {screen} from '@testing-library/react'

import {useIsSharedThread} from '../../hooks/use-is-shared-thread'
import {ContentPreviewProvider} from '../ContentPreview/ContentPreviewContext'
import {Header} from '../Header'

jest.mock('@github-ui/react-core/use-app-payload')
jest.mock('../../hooks/use-is-shared-thread')
jest.mocked(useAppPayload).mockReturnValue({
  copilotChatSettingEnabled: true,
  ssoOrganizations: [],
  apiURL: '',
  canShareThread: true,
})

const mockUseIsSharedThread = jest.mocked(useIsSharedThread)

function TestHeaderSetup({
  showModelPicker = true,
  showPreviewPaneButton = true,
  selectedThreadID = 'thread-1',
  testReducerState = {
    ...getDefaultReducerState('2', undefined, 'immersive'),
    messagesLoading: {state: 'loaded' as const, error: null},
  },
}) {
  const mockProviderProps = {
    ...getCopilotChatProviderProps(),
    selectedThreadID,
  }

  return (
    <CopilotChatProvider {...mockProviderProps} mode="immersive" threadId={null} testReducerState={testReducerState}>
      <ContentPreviewProvider>
        <Header showModelPicker={showModelPicker} showPreviewPaneButton={showPreviewPaneButton} />
      </ContentPreviewProvider>
    </CopilotChatProvider>
  )
}

describe('ShareConversationButton visibility', () => {
  beforeEach(() => {
    // Reset all mocks before each test
    jest.clearAllMocks()
    // Default mock return value
    mockUseIsSharedThread.mockReturnValue(false)
  })

  it('should show ShareConversationButton when all conditions are met', () => {
    render(<TestHeaderSetup />)

    expect(screen.getByRole('button', {name: 'Share conversation'})).toBeInTheDocument()
  })

  it('should not show ShareConversationButton when thread is a shared thread', () => {
    mockUseIsSharedThread.mockReturnValue(true)

    render(<TestHeaderSetup />)

    expect(screen.queryByRole('button', {name: 'Share conversation'})).not.toBeInTheDocument()
  })

  it('should not show ShareConversationButton when canShareThread is false', () => {
    jest.mocked(useAppPayload).mockReturnValue({
      canShareThread: false,
    })

    render(<TestHeaderSetup />)

    expect(screen.queryByRole('button', {name: 'Share conversation'})).not.toBeInTheDocument()
  })

  it('should not show ShareConversationButton when messages are still loading', () => {
    render(
      <CopilotChatProvider
        {...{
          ...getCopilotChatProviderProps(),
          selectedThreadID: 'thread-1',
        }}
        mode="immersive"
        threadId={null}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          messagesLoading: {state: 'loading', error: null},
        }}
      >
        <ContentPreviewProvider>
          <Header />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    expect(screen.queryByRole('button', {name: 'Share conversation'})).not.toBeInTheDocument()
  })
})
