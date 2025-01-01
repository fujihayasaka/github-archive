// Only sent to create an initial Spark generation. Does not require editor state or other fields (for now).
export const WorkbenchGeneratePayload = {
  type: 'workbench-state',
  step: 'generate',
}

export type FileDescription = {
  fileName: string
  content: string
}

export type WorkbenchAgentReference = {
  type: 'github.workbenchState'
  data: WorkbenchIterationPayload | typeof WorkbenchGeneratePayload
}

export type WorkbenchIterationPayload = {
  type: 'workbench-state'
  workbench_id: number
  step: 'refine'
  custom_instructions?: string
  include_reminders_reasoning?: boolean
  include_api_key_instructions?: boolean
  editor_state: {
    files: {
      [key: string]: FileDescription
    }
    suggestion_rejected_history?: string[]
    refinement_history: string[]
    current_suggestions?: string[]
  }
}
