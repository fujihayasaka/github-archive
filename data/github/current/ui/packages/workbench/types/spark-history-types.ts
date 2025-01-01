import type {ImageReference} from '@github-ui/copilot-chat/utils/copilot-chat-types'

// Only sent to create an initial Spark generation. Does not require editor state or other fields (for now).

type WorkbenchGeneratePayloadType = {
  type: 'workbench-state'
  step: 'generate'
  version: 'v3'
}

export const WorkbenchGeneratePayload = {
  type: 'workbench-state' as const,
  step: 'generate' as const,
}

export const WorkbenchTitlePayload = {
  type: 'workbench-state',
  step: 'generate_title',
}

export type FileDescription = {
  fileName: string
  content?: string
  editType?: 'create' | 'update' | 'delete' | 'rename'
}

export type WorkbenchAgentReference = {
  type: 'github.workbenchState'
  data: WorkbenchIterationPayload | WorkbenchGeneratePayloadType | typeof WorkbenchTitlePayload
}

export type WorkbenchIterationPayload = {
  type: 'workbench-state'
  workbench_id: number
  version: 'v3'
  step: 'refine'
  custom_instructions?: string
  include_reminders_reasoning?: boolean
  include_api_key_instructions?: boolean
  editor_state: {
    files: {
      [key: string]: FileDescription
    }
  }
  suggestion_rejected_history?: string[]
  refinement_history: string[]
  current_suggestions?: string[]
  image?: ImageReference
}
