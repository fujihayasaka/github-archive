import {OpenPanelContext} from '@github-ui/code-view-shared/contexts/OpenPanelContext'
import {type PropsWithChildren, useMemo} from 'react'

import {useWorkspaceEditorUIState} from './WorkspaceEditorUIContext'

/** stable reference to an empty function */
const noop = () => {}

/**
 * Simple implementation of OpenPanelContext that just forwards the right panel
 * state from the app state context. This allows the file tree to collapse to an overlay
 * at a larger breakpoint when the panel is open.
 */
export function OpenPanelProvider({children}: PropsWithChildren) {
  const {rightPanel} = useWorkspaceEditorUIState()

  const contextData = useMemo(() => {
    return {
      openPanel: rightPanel,
      setOpenPanel: noop,
    }
  }, [rightPanel])

  return <OpenPanelContext.Provider value={contextData}>{children}</OpenPanelContext.Provider>
}
