export const RuleSeverity = {
  None: 'none',
  Note: 'note',
  Warning: 'warning',
  Error: 'error',
} as const

export type RuleSeverity = (typeof RuleSeverity)[keyof typeof RuleSeverity]
