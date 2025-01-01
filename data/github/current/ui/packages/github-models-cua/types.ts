export type Step = {
  role: string
  content: string
  audience: string
  end_turn: boolean | null
  id: string
  channel: string | null
  tool_name: string | null
  repr: string
  meta: string // json
}

export type StepMessage = {
  id: string
  author: {role: string; name: string}
  content:
    | {
        content_type: 'text'
        parts: string[]
      }
    | {
        content_type: 'computer_output'
        screenshot: {
          content_type: string
          format: string
          payload: string
        }
      }
}
