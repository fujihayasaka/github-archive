import {FilesPageInfoProvider} from '@github-ui/code-view-shared/contexts/FilesPageInfoContext'
import {CopilotChatProvider} from '@github-ui/copilot-chat/CopilotChatContext'
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

import {ApiClientProvider} from './components/ApiClientProvider'
import {CopilotContextProvider} from './contexts/CopilotContext'
import {CurrentPullRequestProvider} from './contexts/CurrentPullRequestProvider'
import {FilesContextProvider} from './contexts/FilesContext'
import {FocusContextProvider} from './contexts/FocusContext'
import {SuggestionContextProvider} from './contexts/SuggestionContext'
import {TerminalContextProvider} from './contexts/TerminalContext'
import {WorkspaceEditorAppContextProvider} from './contexts/WorkspaceEditorAppContext'
import {WorkspaceEditorUIProvider} from './contexts/WorkspaceEditorUIContext'
import {AnalyticsContext} from './telemetry/AnalyticsContext'
import {getSelectedThreadID} from './utilities/copilot-chat'
import {uuid} from './utilities/uuid'
import type {WorkspaceEditorPullRequestPayload, WorkspaceEditorRoutePayload} from './utilities/workspace-editor-types'

// App runtime session ID.
const APP_RUNTIME_SESSION_ID = uuid()

// Session storage key to store the browser session ID.
const WORKSPACE_EDITOR_SESSION_ID_KEY = 'hadron_editor_session_id'

// Get a browser session ID that might have been persisted in
// session storage. If it's not there, a new ID is generated.
const getBrowserSessionId = (): string => {
  // check if we have a session ID in local storage
  const maybe_session_id = sessionStorage.getItem(WORKSPACE_EDITOR_SESSION_ID_KEY)
  if (maybe_session_id) {
    return maybe_session_id
  }

  // Generate new session ID, and try to read it back again.
  // We are reading it back from the session storage to make sure that the storage
  // is functional and the value was successfully persisted in it, otherwise the value
  // will change on every page reload which breaks semantics of the browser session ID.
  sessionStorage.setItem(WORKSPACE_EDITOR_SESSION_ID_KEY, uuid())
  return sessionStorage.getItem(WORKSPACE_EDITOR_SESSION_ID_KEY) ?? 'cannot-use-session-storage'
}

/**
 * The App component is used to render content which should be present on _all_ routes within this app
 */
export function App(props: {children?: React.ReactNode}) {
  const payload = useRoutePayload<WorkspaceEditorRoutePayload & WorkspaceEditorPullRequestPayload>()
  const {copilotAccessAllowed, refInfo, path, pullRequest, repo, copilot, findFileWorkerPath} = payload
  const [user] = React.useState(payload?.currentUser)

  // Create global telemetry context metadata.
  const metadata = useCallback(() => {
    return {
      pull_request_id: payload.pullRequest.id,
      pull_request_number: payload.pullRequest.number,
      feature_flags: {}, // TODO: add feature flags
      repository_id: payload.repo.id,
      branch_name: payload.pullRequest.headBranch,
      runtime_session_id: APP_RUNTIME_SESSION_ID,
      browser_session_id: getBrowserSessionId(),
      copilot_access_allowed: payload.copilotAccessAllowed,
    }
  }, [
    payload.pullRequest.id,
    payload.pullRequest.number,
    payload.pullRequest.headBranch,
    payload.repo.id,
    payload.copilotAccessAllowed,
  ])

  const threadID = getSelectedThreadID(repo.ownerLogin, repo.name, pullRequest.number)

  // for registering behavior that is loaded already via component
  const commands = {
    'workspace-editor:toggle-file-tree-pane': noop,
    [isMacOS() ? 'workspace-editor:escape-editor--mac' : 'workspace-editor:escape-editor']: noop,
  }

  return (
    <ScreenSizeProvider initialValue={ScreenSize.xxxlarge}>
      <GlobalCommands commands={commands} />
      <AnalyticsContext name="global" metadata={metadata}>
        <WorkspaceEditorAppContextProvider>
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
                            <FilesContextProvider>
                              <TerminalContextProvider>
                                <SuggestionContextProvider>
                                  <FocusContextProvider>{props.children}</FocusContextProvider>
                                </SuggestionContextProvider>
                              </TerminalContextProvider>
                            </FilesContextProvider>
                          </WorkspaceEditorUIProvider>
                        </CopilotChatProvider>
                      </ApiClientProvider>
                    </CopilotContextProvider>
                  </FileTreeControlProvider>
                </CurrentPullRequestProvider>
              </CurrentRepositoryProvider>
            </FilesPageInfoProvider>
          </CurrentUserProvider>
        </WorkspaceEditorAppContextProvider>
      </AnalyticsContext>
    </ScreenSizeProvider>
  )
}
