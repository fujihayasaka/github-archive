import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {parse} from 'jsonc-parser'
import {useCallback} from 'react'

import {useCurrentPullRequest} from '../contexts/CurrentPullRequestProvider'
import {useFilesContext} from '../contexts/FilesContext'
import {useWorkspaceEditorAppContext} from '../contexts/WorkspaceEditorAppContext'
import type {
  ConnectedCodespaceData,
  TerminalTasks,
  WorkspaceEditorRoutePayload,
} from '../utilities/workspace-editor-types'

export function useFetchRepoTerminalTasks(codespacesData: ConnectedCodespaceData): {
  fetchRepoTasks: () => Promise<TerminalTasks | undefined>
} {
  const {repo} = useRoutePayload<WorkspaceEditorRoutePayload>()
  const {pullRequest} = useCurrentPullRequest()
  const {blobService} = useWorkspaceEditorAppContext()
  const {getCurrentFileContent} = useFilesContext()

  const fetchRepoTasks = useCallback(async () => {
    const path = codespacesData.codespaceInfo?.environment_data.devcontainer_path ?? '.devcontainer/devcontainer.json'

    try {
      const response = await blobService.getBlob(
        path,
        repo.ownerLogin,
        pullRequest.number,
        repo.name,
        pullRequest.headSHA,
      )
      if (!response.ok) {
        return undefined
      }

      const serverContent = response.payload.blobContents
      if (!serverContent) {
        return undefined
      }

      const {content: devcontainer} = getCurrentFileContent(path, serverContent)
      if (!devcontainer) {
        return undefined
      }

      const jsonObject = parse(devcontainer)
      if (Object.keys(jsonObject).length !== 0) {
        return jsonObject.tasks as Record<string, string>
      }
    } catch {
      // Failed parsing build/test/run
    }
  }, [
    blobService,
    codespacesData.codespaceInfo?.environment_data.devcontainer_path,
    getCurrentFileContent,
    pullRequest.headSHA,
    pullRequest.number,
    repo.name,
    repo.ownerLogin,
  ])

  return {fetchRepoTasks}
}
