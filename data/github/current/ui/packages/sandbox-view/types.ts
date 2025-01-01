export type PreviewData = {
  content: string
  scripts?: string
  styles?: string
}

export const RenderState = {
  ERROR: 'ERROR',
  LOADING: 'LOADING',
  LOADED: 'LOADED',
  READY: 'READY',
} as const

export type RenderState = (typeof RenderState)[keyof typeof RenderState]

export interface RenderMessage {
  type: 'render'
  body: string
  payload:
    | null
    | undefined
    | {
        height?: number
        error?: string | null
      }
}

export interface RenderCommand {
  type: 'render:cmd'
  body?: unknown
}
