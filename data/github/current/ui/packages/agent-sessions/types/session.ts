export type Delta = {
  content?: string
  role?: string
  reasoning_text?: string
  tool_calls?: Array<{
    function: {
      arguments: string
      name: ToolName
      result?: string
    }
    id: string
    type: string
    index: number
  }>
}

export type StreamingMessage = {
  type?: string
  id: string
  created: number
  model: string
  object: string
  choices: Choice[]
}

export type Choice = {
  finish_reason: string
  delta: Delta
}

export type LogEntry = {
  id: string
  choices: Choice[]
} & Record<string, unknown>

export type Session = {
  id: string
  name: string
  user_id: number
  agent_id: number
  state: SessionState
  owner_id: number
  repo_id: number
  resource_type: string
  resource_id: number
  created_at: string // ISO 8601 string
  last_updated_at: string // ISO 8601 string
  completed_at?: string // Optional ISO 8601 string,
  workflow_run_id: number
  log_entries: LogEntry[]
  error: {
    message: string
  } | null
  premium_requests: number
}

// TODO: Improve this type as we learn more about the real data
export const SessionState = {
  InProgress: 'in_progress',
  Completed: 'completed',
  Failed: 'failed',
  Idle: 'idle',
  WaitingForUser: 'waiting_for_user',
  TimedOut: 'timed_out',
  Cancelled: 'cancelled',
} as const
export type SessionState = (typeof SessionState)[keyof typeof SessionState]

export function getReadableSessionState(state: SessionState) {
  switch (state) {
    case SessionState.InProgress:
      return 'In progress'
    case SessionState.Completed:
      return 'Completed'
    case SessionState.Failed:
      return 'Failed'
    case SessionState.Idle:
      return 'Idle'
    case SessionState.WaitingForUser:
      return 'Waiting for User'
    case SessionState.TimedOut:
      return 'Timed out'
    case SessionState.Cancelled:
      return 'Cancelled'
    default:
      return 'Unknown'
  }
}

// Custom MCP can give us a tool name we can't predict so we need to allow for any string
export type ToolName = 'bash' | 'think' | 'str_replace_editor' | 'report_progress' | 'reply_to_comment' | string

export type BashToolArgs = {
  command: string
}

export type AsyncBashToolArgs = {
  command: string
  sessionId: string
}

export type ReadAsyncBashToolArgs = {
  sessionId: string
}

export type StopAsyncBashToolArgs = {
  sessionId: string
}

export type ThinkToolArgs = {
  thought: string
}

export type StrReplaceEditorToolArgs = {
  command: 'view' | 'create' | 'str_replace' | 'insert' | 'undo_edit'
  path: string
  view_range?: [number, number]
  insert_line?: number
}

export type ReportProgressToolArgs = {
  prDescription: string
  commitMessage: string
}

export type ReplyToCommentToolArgs = {
  comment_id: string
  reply: string
}

export type ToolArgs =
  | BashToolArgs
  | ThinkToolArgs
  | StrReplaceEditorToolArgs
  | ReportProgressToolArgs
  | ReplyToCommentToolArgs
  | AsyncBashToolArgs
  | ReadAsyncBashToolArgs
  | StopAsyncBashToolArgs
