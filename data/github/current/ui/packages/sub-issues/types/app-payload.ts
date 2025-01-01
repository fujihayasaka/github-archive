export type AppPayload =
  | {
      current_user_settings?: {
        use_monospace_font: boolean
      }
    }
  | undefined
