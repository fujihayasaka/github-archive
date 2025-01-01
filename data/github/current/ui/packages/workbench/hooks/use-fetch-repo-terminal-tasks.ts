import {useRoutePayload} from '@github-ui/react-core/use-route-payload'
import {parse} from 'jsonc-parser'
import {useCallback} from 'react'

import type {ConnectedCodespaceData, TerminalTasks} from '../../workspace-editor/utilities/workspace-editor-types'
import {useFilesContext} from '../contexts/FilesContext'
import {useWorkbenchEditorAppContext} from '../contexts/WorkbenchEditorAppContext'
import type {WorkbenchRoutePayload} from '../types/workbench-types'

export function useFetchRepoTerminalTasks(codespacesData: ConnectedCodespaceData): {
  fetchRepoTasks: () => Promise<TerminalTasks | undefined>
} {
  const {workbench} = useRoutePayload<WorkbenchRoutePayload>()
  const {blobService} = useWorkbenchEditorAppContext()
  const {getCurrentFileContent} = useFilesContext()

  const fetchRepoTasks = useCallback(async () => {
    const path = codespacesData.codespaceInfo?.environment_data.devcontainer_path ?? '.devcontainer/devcontainer.json'

    try {
      const response = await blobService.getBlob(path, workbench.id)
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
    workbench.id,
  ])

  return {fetchRepoTasks}
}
