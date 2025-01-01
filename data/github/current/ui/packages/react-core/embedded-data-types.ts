export interface EmbeddedData {
  // payload per route
  payload: unknown
  // payload for the app
  appPayload?: Record<string, unknown>
  title?: string
  meta?: {title?: string}
}

export interface EmbeddedPartialData {
  props: object
}
