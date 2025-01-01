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
import React, {useCallback} from 'react'

import {ApiClientProvider} from '../workspace-editor/components/ApiClientProvider'
import {CopilotContextProvider} from '../workspace-editor/contexts/CopilotContext'
import {CurrentPullRequestProvider} from '../workspace-editor/contexts/CurrentPullRequestProvider'
import {FocusContextProvider} from '../workspace-editor/contexts/FocusContext'
import {WorkspaceEditorUIProvider} from '../workspace-editor/contexts/WorkspaceEditorUIContext'
import {AnalyticsContext} from '../workspace-editor/telemetry/AnalyticsContext'
import {uuid} from '../workspace-editor/utilities/uuid'
import type {WorkspaceEditorPullRequestPayload} from '../workspace-editor/utilities/workspace-editor-types'
import {FilesContextProvider} from './contexts/FilesContext'
import {TerminalContextProvider} from './contexts/TerminalContext'
import {WorkbenchEditorAppContextProvider} from './contexts/WorkbenchEditorAppContext'
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
export function App(props: {children?: React.ReactNode}) {
  const payload = useRoutePayload<WorkbenchRoutePayload & WorkspaceEditorPullRequestPayload>()
  const {copilotAccessAllowed, refInfo, path, repo, copilot, findFileWorkerPath, workbench} = payload
  const [user] = React.useState(payload?.currentUser)
  // Create global telemetry context metadata.
  const metadata = useCallback(() => {
    return {
      pull_request_id: payload?.pullRequest?.id,
      pull_request_number: payload?.pullRequest?.number,
      feature_flags: {}, // TODO: add feature flags
      repository_id: payload?.repo?.id,
      branch_name: payload?.pullRequest?.headBranch,
      runtime_session_id: APP_RUNTIME_SESSION_ID,
      browser_session_id: getBrowserSessionId(),
      copilot_access_allowed: payload.copilotAccessAllowed,
    }
  }, [
    payload?.pullRequest?.id,
    payload?.pullRequest?.number,
    payload?.pullRequest?.headBranch,
    payload?.repo?.id,
    payload.copilotAccessAllowed,
  ])

  const threadID = getSelectedThreadID(workbench.id)

  // for registering behavior that is loaded already via component
  const commands = {
    'workspace-editor:toggle-file-tree-pane': noop,
    [isMacOS() ? 'workspace-editor:escape-editor--mac' : 'workspace-editor:escape-editor']: noop,
  }

  return (
    <ScreenSizeProvider initialValue={ScreenSize.xxxlarge}>
      <GlobalCommands commands={commands} />
      <AnalyticsContext name="global" metadata={metadata}>
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
                      <ApiClientProvider>
                        <CopilotChatProvider
                          topic={copilot.currentTopic}
                          workerPath={findFileWorkerPath}
                          threadId={threadID}
                          refs={[]} // TODO
                          mode="assistive"
                          ssoOrganizations={copilot.ssoOrganizations}
                          copilotChatPayload={copilot}
                        >
                          <WorkspaceEditorUIProvider>
                            <ContentPreviewProvider>
                              <FilesContextProvider>
                                <TerminalContextProvider>
                                  <FocusContextProvider>{props.children}</FocusContextProvider>
                                </TerminalContextProvider>
                              </FilesContextProvider>
                            </ContentPreviewProvider>
                          </WorkspaceEditorUIProvider>
                        </CopilotChatProvider>
                      </ApiClientProvider>
                    </CopilotContextProvider>
                  </FileTreeControlProvider>
                </CurrentPullRequestProvider>
              </CurrentRepositoryProvider>
            </FilesPageInfoProvider>
          </CurrentUserProvider>
        </WorkbenchEditorAppContextProvider>
      </AnalyticsContext>
    </ScreenSizeProvider>
  )
}
