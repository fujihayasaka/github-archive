import type {MediaContentItem} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import type {WorkspaceEditorRoutePayload} from '@github-ui/workspace-editor/utilities/workspace-editor-types'

import type {DeploymentVisibility} from './deployment-types'
import type {FileDescription} from './spark-history-types'

export interface WorkbenchRoutePayload extends WorkspaceEditorRoutePayload {
  deploymentVisibility?: DeploymentVisibility
  friendlyName?: string
  login?: string
  workbench: Workbench
  deploy?: Deploy
  acaJwtInfo?: ACAJwtInfo
  previewDeploy?: Deploy
}

export interface Deploy {
  createdAt: string
  deployLogin: string
  displayName: string
  domainBase: string
  revision?: string
}

export interface ACAJwtInfo {
  appName: string
  payload: string
  proxyPayload: string
  userLogin: string
}

export interface Iteration {
  iteration_type: 'ai' | 'user'
  prompt?: string
  sha?: string
  files: Record<string, FileDescription>
  id?: number
  parentId?: number | null
  suggestions?: string[]
  error?: {message: string}
}

export interface Workbench {
  id: string
  name: string
  files: Record<string, FileDescription>
  previousRefinements: Iteration[] // User entered refinement prompts & previously selected suggestions
  title: string // Model generated title
  description: string // Model generated description
  suggestions: string[] // Model generated refinement suggestions
  runtimePermanentName: string // The immutable name of the runtime that backs this Spark
  friendlyName: string
  shouldGenerateInitialPrompt: boolean
  updatedAt?: string
  deployUrl?: string
  favorite?: boolean
  currentRefinementId?: number | null
  repositoryUrl?: string
  billableOwner: {
    id: number
    login: string
    type: 'User' | 'Organization'
  }
  cloudspace_id: string
  cloudspace_active?: boolean
  cloudspace_name?: string
  cloudspace_guid?: string
  cloudspace_last_used_at?: string
}

export type WorkbenchMediaContentItem = Omit<MediaContentItem, 'mediaType'> & {media_type: string}

export const Panel = {
  THEME: 'theme',
  AI: 'ai',
  ASSETS: 'assets',
  DATA: 'data',
  ITERATE: 'iterate',
  LOGS: 'logs',
} as const
export type Panel = (typeof Panel)[keyof typeof Panel]

export const Region = {
  ...Panel,
  HISTORY: 'history', // removed?
  EDITOR: 'editor',
  PREVIEW: 'preview',
  TARGETED_EDITS: 'targetedEdits',
  DEPLOY_BUTTON: 'deployButton',
  SETTINGS: 'settings',
} as const
export type Region = (typeof Region)[keyof typeof Region]

export type SparkAgentModel = 'claude-3.7-sonnet' | 'claude-sonnet-4'

export type WorkingMode = 'code' | 'split' | 'preview'
