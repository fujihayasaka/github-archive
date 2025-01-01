import './mocks'

import {FilesPageInfoProvider} from '@github-ui/code-view-shared/contexts/FilesPageInfoContext'
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {FileTreeControlProvider} from '@github-ui/repos-file-tree-view'
import type {PropsWithChildren} from 'react'

import {CurrentPullRequestProvider} from '../contexts/CurrentPullRequestProvider'
import {FilesContextProvider} from '../contexts/FilesContext'
import {FocusContextProvider} from '../contexts/FocusContext'
import {SuggestionContextProvider} from '../contexts/SuggestionContext'
import {TerminalContextProvider} from '../contexts/TerminalContext'
import {WorkspaceEditorAppContextProvider} from '../contexts/WorkspaceEditorAppContext'
import {WorkspaceEditorUIProvider} from '../contexts/WorkspaceEditorUIContext'
import {AnalyticsContext} from '../telemetry/AnalyticsContext'
import type {WorkspaceEditorPullRequestPayload, WorkspaceEditorRoutePayload} from '../utilities/workspace-editor-types'

export function TestComponentWrapper({children}: PropsWithChildren) {
  const payload = useRoutePayload<WorkspaceEditorRoutePayload & WorkspaceEditorPullRequestPayload>()
  const {repo, refInfo, copilotAccessAllowed} = payload
  const metadata = () => ({
    pull_request_id: payload.pullRequest.id,
    pull_request_number: payload.pullRequest.number,
    feature_flags: {},
    repository_id: payload.repo.id,
    branch_name: payload.pullRequest.headBranch,
    runtime_session_id: 1,
    browser_session_id: 1,
    copilot_access_allowed: true,
  })

  return (
    <AnalyticsContext name="global" metadata={metadata}>
      <WorkspaceEditorAppContextProvider>
        <WorkspaceEditorUIProvider>
          <CurrentPullRequestProvider>
            <FileTreeControlProvider>
              <FilesContextProvider>
                <FilesPageInfoProvider
                  refInfo={refInfo}
                  path="path/to/file"
                  action="blob"
                  copilotAccessAllowed={copilotAccessAllowed}
                >
                  <CurrentRepositoryProvider repository={repo}>
                    <TerminalContextProvider>
                      <SuggestionContextProvider>
                        <FocusContextProvider>{children}</FocusContextProvider>
                      </SuggestionContextProvider>
                    </TerminalContextProvider>
                  </CurrentRepositoryProvider>
                </FilesPageInfoProvider>
              </FilesContextProvider>
            </FileTreeControlProvider>
          </CurrentPullRequestProvider>
        </WorkspaceEditorUIProvider>
      </WorkspaceEditorAppContextProvider>
    </AnalyticsContext>
  )
}
