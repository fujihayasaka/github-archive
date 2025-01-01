import {FilesPageInfoProvider} from '@github-ui/code-view-shared/contexts/FilesPageInfoContext'
import {CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
// eslint-disable-next-line @github-ui/github-monorepo/restrict-package-deep-imports
import {ContentPreviewProvider} from '@github-ui/copilot-immersive-v1/components/ContentPreview/ContentPreviewContext'
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {CurrentUserProvider} from '@github-ui/current-user'
import {isMacOS} from '@github-ui/get-os'
import {noop} from '@github-ui/noop'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {FileTreeControlProvider} from '@github-ui/repos-file-tree-view'
// eslint-disable-next-line no-restricted-imports
import {ScreenSize, ScreenSizeProvider} from '@github-ui/screen-size'
import {GlobalCommands} from '@github-ui/ui-commands'
import {CopilotContextProvider} from '@github-ui/workspace-editor/contexts/CopilotContext'
import {CurrentPullRequestProvider} from '@github-ui/workspace-editor/contexts/CurrentPullRequestProvider'
import {FocusContextProvider} from '@github-ui/workspace-editor/contexts/FocusContext'
import {WorkspaceEditorUIProvider} from '@github-ui/workspace-editor/contexts/WorkspaceEditorUIContext'
import {uuid} from '@github-ui/workspace-editor/utilities/uuid'
import type {WorkspaceEditorPullRequestPayload} from '@github-ui/workspace-editor/utilities/workspace-editor-types'
import React, {useCallback} from 'react'

import {CodespaceContextProvider} from './contexts/CodespaceContext'
import {ContentFilterProvider} from './contexts/ContentFilterContext'
import {DatabaseProvider} from './contexts/DatabaseContext'
import {EditorContextProvider} from './contexts/EditorContext'
import {FilesContextProvider} from './contexts/FilesContext'
import {FileSyncerContextProvider} from './contexts/FileSyncerContext'
import {IterationHistoryProvider} from './contexts/IterationHistoryContext'
import {ServerEventsProvider} from './contexts/ServerEventsContext'
import {TargetedEditsProvider} from './contexts/TargetedEditsContext'
import {TerminalContextProvider} from './contexts/TerminalContext'
import {WorkbenchContextProvider} from './contexts/WorkbenchContext'
import {WorkbenchEditorAppContextProvider} from './contexts/WorkbenchEditorAppContext'
import {WorkbenchPreviewProvider} from './contexts/WorkbenchPreviewContext'
import {WorkbenchStoreProvider} from './contexts/WorkbenchStoreContext'
import {WorkbenchUIContextProvider} from './contexts/WorkbenchUIContext'
import {AnalyticsContextProvider} from './telemetry/AnalyticsContext'
import type {WorkbenchRoutePayload} from './types/workbench-types'
import {getSelectedThreadID} from './utilities/copilot-chat'

// App runtime session ID.
const APP_RUNTIME_SESSION_ID = uuid()

// Session storage key to store the browser session ID.
const WORKBENCH_SESSION_ID = 'workbench_session_id'

// Get a browser session ID that might have been persisted in
// session storage. If it's not there, a new ID is generated.
const getBrowserSessionId = (): string => {
  // check if we have a session ID in local storage
  const maybe_session_id = sessionStorage.getItem(WORKBENCH_SESSION_ID)
  if (maybe_session_id) {
    return maybe_session_id
  }

  // Generate new session ID, and try to read it back again.
  // We are reading it back from the session storage to make sure that the storage
  // is functional and the value was successfully persisted in it, otherwise the value
  // will change on every page reload which breaks semantics of the browser session ID.
  sessionStorage.setItem(WORKBENCH_SESSION_ID, uuid())
  return sessionStorage.getItem(WORKBENCH_SESSION_ID) ?? 'cannot-use-session-storage'
}

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function SharedWorkbenchContext(props: {children?: React.ReactNode}) {
  const payload = useRoutePayload<WorkbenchRoutePayload & WorkspaceEditorPullRequestPayload>()
  const {copilotAccessAllowed, refInfo, path, repo, copilot, findFileWorkerPath, workbench} = payload
  const [user] = React.useState(payload?.currentUser)

  // Create global telemetry context metadata.
  const metadata = useCallback(() => {
    return {
      feature_flags: {}, // TODO: add feature flags
      workbench_id: workbench.id,
      runtime_permanent_name: workbench.runtimePermanentName,
      runtime_session_id: APP_RUNTIME_SESSION_ID,
      browser_session_id: getBrowserSessionId(),
      copilot_access_allowed: payload.copilotAccessAllowed,
    }
  }, [payload.copilotAccessAllowed, workbench.id, workbench.runtimePermanentName])

  const threadID = getSelectedThreadID(workbench.id)

  // for registering behavior that is loaded already via component
  const commands = {
    'workspace-editor:toggle-file-tree-pane': noop,
    [isMacOS() ? 'workspace-editor:escape-editor--mac' : 'workspace-editor:escape-editor']: noop,
  }

  return (
    <ScreenSizeProvider initialValue={ScreenSize.xxxlarge}>
      <GlobalCommands commands={commands} />
      <AnalyticsContextProvider name="global" metadata={metadata}>
        <WorkbenchEditorAppContextProvider>
          <CurrentUserProvider user={user}>
            <FilesPageInfoProvider
              refInfo={refInfo}
              path={path}
              action="blob"
              copilotAccessAllowed={copilotAccessAllowed}
            >
              <CurrentRepositoryProvider repository={repo}>
                <CurrentPullRequestProvider>
                  <FileTreeControlProvider>
                    <CopilotContextProvider>
                      <CopilotChatProvider
                        topic={copilot.currentTopic}
                        workerPath={findFileWorkerPath}
                        threadId={threadID}
                        refs={[]} // TODO
                        mode="assistive"
                        ssoOrganizations={copilot.ssoOrganizations}
                        copilotChatPayload={copilot}
                      >
                        <WorkbenchStoreProvider>
                          <WorkbenchContextProvider>
                            <WorkspaceEditorUIProvider>
                              <ContentPreviewProvider>
                                <CodespaceContextProvider>
                                  <FileSyncerContextProvider>
                                    <FilesContextProvider>
                                      <EditorContextProvider>
                                        <TerminalContextProvider>
                                          <DatabaseProvider runtimePermanentName={workbench.runtimePermanentName}>
                                            <WorkbenchPreviewProvider>
                                              <TargetedEditsProvider>
                                                <IterationHistoryProvider>
                                                  <FocusContextProvider>
                                                    <ContentFilterProvider>
                                                      <WorkbenchUIContextProvider>
                                                        <ServerEventsProvider>{props.children}</ServerEventsProvider>
                                                      </WorkbenchUIContextProvider>
                                                    </ContentFilterProvider>
                                                  </FocusContextProvider>
                                                </IterationHistoryProvider>
                                              </TargetedEditsProvider>
                                            </WorkbenchPreviewProvider>
                                          </DatabaseProvider>
                                        </TerminalContextProvider>
                                      </EditorContextProvider>
                                    </FilesContextProvider>
                                  </FileSyncerContextProvider>
                                </CodespaceContextProvider>
                              </ContentPreviewProvider>
                            </WorkspaceEditorUIProvider>
                          </WorkbenchContextProvider>
                        </WorkbenchStoreProvider>
                      </CopilotChatProvider>
                    </CopilotContextProvider>
                  </FileTreeControlProvider>
                </CurrentPullRequestProvider>
              </CurrentRepositoryProvider>
            </FilesPageInfoProvider>
          </CurrentUserProvider>
        </WorkbenchEditorAppContextProvider>
      </AnalyticsContextProvider>
    </ScreenSizeProvider>
  )
}
