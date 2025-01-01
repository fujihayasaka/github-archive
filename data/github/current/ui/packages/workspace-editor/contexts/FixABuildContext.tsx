import {useChatManager} from '@github-ui/copilot-chat/CopilotChatManagerContext'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {createContext, useCallback, useContext, useMemo, useState} from 'react'

import {ReadLocalWorkspaceFileSkill} from '../../copilot-chat/utils/skills/read-local-workspace-file'
import {useLocalFileData} from '../hooks/use-local-file-data'
import {
  formatChangedFilesAsReference,
  formatPullRequestAsReference,
  formatTerminalOutputAsReference,
  USER_MESSAGE,
} from '../utilities/fix-a-build-helpers'
import {PROMPT} from '../utilities/fix-a-build-prompt'
import type {CommandResult} from '../utilities/terminal-reducer'
import type {WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {RightPanelType} from '../utilities/workspace-editor-ui-reducer'
import {useWorkspaceEditorUIDispatch, useWorkspaceEditorUIState} from './WorkspaceEditorUIContext'

type FixABuildContextData = {
  fixABuild: () => Promise<void>
  loading: boolean
}

const FixABuildContext = createContext<FixABuildContextData | undefined>(undefined)

export function FixABuildContextProvider({command, children}: {command: CommandResult; children: React.ReactNode}) {
  const [loading, setLoading] = useState(false)
  const manager = useChatManager()
  const uiDispatch = useWorkspaceEditorUIDispatch()
  const {rightPanel} = useWorkspaceEditorUIState()

  const {repo, pullRequest, refInfo} = useRoutePayload<WorkspaceEditorRoutePayload>()

  const {getChangedFiles} = useLocalFileData()
  const changedFiles = getChangedFiles()

  const references = useMemo(() => {
    return [
      formatTerminalOutputAsReference(command.output, repo, pullRequest.id),
      formatChangedFilesAsReference(changedFiles),
      formatPullRequestAsReference(pullRequest, repo, refInfo),
    ]
  }, [changedFiles, command.output, pullRequest, refInfo, repo])

  const fixABuild = useCallback(async () => {
    setLoading(true)
    if (rightPanel !== RightPanelType.Chat) {
      uiDispatch({type: 'TOGGLE_RIGHT_PANEL', rightPanel: RightPanelType.Chat, rightPanelButton: undefined})
    }

    const threadResponse = await manager.service.createThread()
    const thread = threadResponse.ok ? threadResponse.payload : null
    await manager.selectThread(thread)

    await manager.sendChatMessage({
      thread,
      content: USER_MESSAGE,
      references,
      customInstructions: PROMPT,
      tools: [ReadLocalWorkspaceFileSkill.schema()],
    })

    setLoading(false)
  }, [manager, references, rightPanel, uiDispatch])

  const value = useMemo(() => {
    return {fixABuild, command, loading}
  }, [fixABuild, command, loading])

  return <FixABuildContext.Provider value={value}>{children}</FixABuildContext.Provider>
}

export function useFixABuildContext() {
  const context = useContext(FixABuildContext)
  if (!context) {
    throw new Error('useFixABuildContext must be used within an FixABuildContextProvider')
  }
  return context
}
