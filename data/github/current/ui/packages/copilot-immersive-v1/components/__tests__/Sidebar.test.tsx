import {getCopilotChatProviderProps, getDefaultReducerState} from '@github-ui/copilot-chat/test-utils/mock-data'
import {CopilotChatProvider} from '@github-ui/copilot-chat/utils/CopilotChatContext'
import {render} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {screen} from '@testing-library/react'

import {useIsSharedThread} from '../../hooks/use-is-shared-thread'
import {ContentPreviewProvider} from '../ContentPreview/ContentPreviewContext'
import {Sidebar} from '../Sidebar'

jest.mock('@github-ui/react-core/use-app-payload')
jest.mocked(useAppPayload).mockReturnValue({
  copilotChatSettingEnabled: true,
  ssoOrganizations: [],
  apiURL: '', // This goes in front of all CAPI calls
  canShareThread: true,
})

jest.mock('../../hooks/use-is-shared-thread')

const mockClosePreviewPane = jest.fn()
jest.mock('../ContentPreview/ContentPreviewContext', () => ({
  ...jest.requireActual('../ContentPreview/ContentPreviewContext'),
  useContentPreview: () => ({
    closePreviewPane: mockClosePreviewPane,
  }),
}))

const timeNow = new Date(Date.now()).toISOString()

describe('Share conversation button', () => {
  beforeEach(() => {
    // Reset all mocks before each test
    jest.clearAllMocks()
    // Default mock return value
  })

  it('is shown in the sidebar kebab menu for all conversations in the sidebar', async () => {
    jest.mocked(useIsSharedThread).mockReturnValue(false)

    const selectedThreadID = '3'

    const {user} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        mode="immersive"
        threadId={null}
        testReducerState={{
          ...getDefaultReducerState(selectedThreadID, undefined, 'immersive'),
          topicLoading: {state: 'loaded', error: null},
          messagesLoading: {state: 'loaded', error: null},
          threads: new Map([
            ['2', {id: '2', name: 'conversation 2', createdAt: timeNow, updatedAt: timeNow}],
            ['3', {id: '3', name: 'conversation 3', createdAt: timeNow, updatedAt: timeNow}],
            ['4', {id: '4', name: 'conversation 4', createdAt: timeNow, updatedAt: timeNow}],
          ]),
        }}
      >
        <ContentPreviewProvider>
          <Sidebar isVisible isPinned={false} isFloating={false} onNewThread={() => {}} onToggle={() => {}} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    const allKebabButtons = screen.getAllByRole('button', {name: 'Manage conversation'})
    expect(allKebabButtons).toHaveLength(3)

    await user.click(allKebabButtons[0]!)
    expect(screen.getByRole('menuitem', {name: 'Rename'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Share'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Delete'})).toBeInTheDocument()

    // thread ID 3 is the selected thread, so this is the only time we expect the share button
    await user.click(allKebabButtons[1]!)
    expect(screen.getByRole('menuitem', {name: 'Rename'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Share'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Delete'})).toBeInTheDocument()

    await user.click(allKebabButtons[2]!)
    expect(screen.getByRole('menuitem', {name: 'Rename'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Share'})).toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Delete'})).toBeInTheDocument()
  })

  it('is not shown for conversations associated with a space', async () => {
    jest.mocked(useIsSharedThread).mockReturnValue(false)

    const selectedThreadID = '3'

    const {user} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        mode="immersive"
        threadId={null}
        testReducerState={{
          ...getDefaultReducerState(selectedThreadID, undefined, 'immersive'),
          topicLoading: {state: 'loaded', error: null},
          messagesLoading: {state: 'loaded', error: null},
          threads: new Map([
            ['2', {id: '2', name: 'conversation 2', createdAt: timeNow, updatedAt: timeNow}],
            ['3', {id: '3', name: 'conversation 3', createdAt: timeNow, updatedAt: timeNow, customCopilotID: 123}],
            ['4', {id: '4', name: 'conversation 4', createdAt: timeNow, updatedAt: timeNow}],
          ]),
        }}
      >
        <ContentPreviewProvider>
          <Sidebar isVisible isPinned={false} isFloating={false} onNewThread={() => {}} onToggle={() => {}} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    const allKebabButtons = screen.getAllByRole('button', {name: 'Manage conversation'})
    expect(allKebabButtons).toHaveLength(3)

    await user.click(allKebabButtons[0]!)
    expect(screen.getByRole('menuitem', {name: 'Rename'})).toBeInTheDocument()
    expect(screen.queryByRole('menuitem', {name: 'Share'})).not.toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Delete'})).toBeInTheDocument()

    // thread ID 3 is the selected thread, we should not see the share button since this thread is associated with a space
    await user.click(allKebabButtons[1]!)
    expect(screen.getByRole('menuitem', {name: 'Rename'})).toBeInTheDocument()
    expect(screen.queryByRole('menuitem', {name: 'Share'})).not.toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Delete'})).toBeInTheDocument()

    await user.click(allKebabButtons[2]!)
    expect(screen.getByRole('menuitem', {name: 'Rename'})).toBeInTheDocument()
    expect(screen.queryByRole('menuitem', {name: 'Share'})).not.toBeInTheDocument()
    expect(screen.getByRole('menuitem', {name: 'Delete'})).toBeInTheDocument()
  })
})

describe('Preview pane closure', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  it('close PreviewPane when sidebar clicked', async () => {
    const {user} = render(
      <CopilotChatProvider
        {...getCopilotChatProviderProps()}
        mode="immersive"
        threadId={null}
        testReducerState={{
          ...getDefaultReducerState('2', undefined, 'immersive'),
          threads: new Map([
            ['2', {id: '2', name: 'conversation 2', createdAt: timeNow, updatedAt: timeNow}],
            ['3', {id: '3', name: 'conversation 3', createdAt: timeNow, updatedAt: timeNow}],
          ]),
        }}
      >
        <ContentPreviewProvider>
          <Sidebar isVisible isPinned={false} isFloating onNewThread={() => {}} onToggle={() => {}} />
        </ContentPreviewProvider>
      </CopilotChatProvider>,
    )

    await user.click(screen.getByRole('link', {name: 'conversation 2'}))

    expect(mockClosePreviewPane).toHaveBeenCalledTimes(1)
  })
})
