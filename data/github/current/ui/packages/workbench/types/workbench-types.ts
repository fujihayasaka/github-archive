import type {WorkspaceEditorRoutePayload} from '../../workspace-editor/utilities/workspace-editor-types'
import type {FileDescription} from './spark-history-types'

export interface WorkbenchRoutePayload extends WorkspaceEditorRoutePayload {
  workbench: Workbench
}

export interface Workbench {
  id: string
  name: string
  files: Record<string, FileDescription>
  initialPrompt: string // aka original topic
  previousRefinements: string[]
  shouldGenerateInitialPrompt: boolean
}
