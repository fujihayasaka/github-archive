import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {createContext, useContext, useMemo, useReducer} from 'react'

import {useFocusedTask} from '../hooks/use-focused-task'
import {useAnalytics} from '../telemetry/use-analytics'
import {getPreferredDiffStyle} from '../utilities/preferences'
import type {WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'
import {
  RightPanelType,
  type WorkspaceEditorUIAction,
  workspaceEditorUIReducer,
  type WorkspaceEditorUIState,
} from '../utilities/workspace-editor-ui-reducer'

/**
 * Context that manages reading and writing client-side state
 */
const WorkspaceEditorUIContext = createContext<{
  state: WorkspaceEditorUIState
  dispatch: React.Dispatch<WorkspaceEditorUIAction>
} | null>(null)

export type WorkspaceEditorUIProviderProps = React.PropsWithChildren

export function WorkspaceEditorUIProvider({children}: WorkspaceEditorUIProviderProps) {
  const {initialTaskId} = useFocusedTask()
  const sendEvent = useAnalytics()
  const payload = useRoutePayload<WorkspaceEditorRoutePayload>()

  const [state, dispatch] = useReducer(workspaceEditorUIReducer(sendEvent), null, initializeState)
  const value = useMemo(() => ({state, dispatch}), [state, dispatch])
  return <WorkspaceEditorUIContext.Provider value={value}>{children}</WorkspaceEditorUIContext.Provider>

  function initializeState(): WorkspaceEditorUIState {
    const openPanel = new URL(document.location.toString(), window.location.origin).searchParams.get('open_panel')
    let rightPanel: RightPanelType
    if (initialTaskId || openPanel === RightPanelType.Suggestions) {
      rightPanel = RightPanelType.Suggestions
    } else if (openPanel === RightPanelType.Chat) {
      rightPanel = RightPanelType.Chat
    } else {
      rightPanel = RightPanelType.None
    }

    return {
      banner: undefined,
      diffStyle: getPreferredDiffStyle() || 'inline',
      rightPanel,
      showDiff: !!payload.showDiff,
    }
  }
}

export function useWorkspaceEditorUIState() {
  const context = useContext(WorkspaceEditorUIContext)
  if (!context) {
    throw new Error('useWorkspaceEditorUIState must be used within a WorkspaceEditorUIProvider')
  }
  return context.state
}

export function useWorkspaceEditorUIDispatch() {
  const context = useContext(WorkspaceEditorUIContext)
  if (!context) {
    throw new Error('useWorkspaceEditorUIDispatcher must be used within a WorkspaceEditorUIProvider')
  }
  return context.dispatch
}
