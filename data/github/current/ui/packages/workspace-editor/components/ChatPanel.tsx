import {Chat} from '@github-ui/copilot-chat/Chat'
import {ChatPortalContainer} from '@github-ui/copilot-chat/components/PortalContainerUtils'
import {useChatState} from '@github-ui/copilot-chat/CopilotChatContext'
import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {isThreadOlderThan4Hours} from '@github-ui/copilot-chat/utils/copilot-chat-helpers'
import type {CopilotChatManager} from '@github-ui/copilot-chat/utils/copilot-chat-manager'
import type {CopilotChatState} from '@github-ui/copilot-chat/utils/copilot-chat-reducer'
import type {CopilotChatThread} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {IconButtonWithTooltip} from '@github-ui/icon-button-with-tooltip'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
// eslint-disable-next-line no-restricted-imports
import {ScreenSizeProvider} from '@github-ui/screen-size'
import {PlusIcon} from '@primer/octicons-react'
import {useEffect} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {setSelectedThreadID} from '../utilities/copilot-chat'
import type {WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {RightSidePanelHeader} from './RightSidePanelComponents'

export interface ChatContainerProps {}

export function ChatContainer({children}: React.PropsWithChildren<ChatContainerProps>) {
  return (
    <ScreenSizeProvider>
      <ChatPortalContainer />
      {children}
    </ScreenSizeProvider>
  )
}

export interface ChatContentProps {}

export function ChatContent(_: ChatContentProps) {
  const {repo} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const state = useChatState()
  const manager = useChatManager()
  const {selectedThreadID} = state

  useEffect(() => {
    loadOrCreateThread(manager, state, selectedThreadID)
    // we only want to run this on the first mount
    // eslint-disable-next-line react-compiler/react-compiler
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // synchronize the selected thread ID with local storage
  useEffect(() => {
    setSelectedThreadID(repo.ownerLogin, repo.name, pullRequest.number, selectedThreadID)
  }, [pullRequest, repo, selectedThreadID])

  return <Chat key={state.selectedThreadID} />
}

export function ChatHeader() {
  const state = useChatState()
  const manager = useChatManager()
  const threadName = manager.getSelectedThread(state)?.name

  return (
    <RightSidePanelHeader
      title={threadName || 'Copilot'}
      rightContent={
        <IconButtonWithTooltip
          hidden={state.messages.length === 0}
          variant="invisible"
          icon={PlusIcon}
          label="New conversation"
          tooltipDirection="w"
          onClick={async () => {
            await manager.selectThread(null)
          }}
        />
      }
    />
  )
}

async function loadOrCreateThread(
  manager: CopilotChatManager,
  state: CopilotChatState,
  selectedThreadID: string | null,
) {
  let thread: CopilotChatThread | null = null
  if (selectedThreadID) {
    if (state.threads.has(selectedThreadID)) {
      thread = state.threads.get(selectedThreadID) ?? null
    } else {
      const threads = await manager.fetchThreads()
      thread = threads?.find(t => t.id === selectedThreadID) ?? null
    }
  }
  if (thread && isThreadOlderThan4Hours(thread)) {
    thread = null
  }

  manager.openChat(thread, 'thread', 'hadron-editor')
}
