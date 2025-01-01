export const ExportJobState = {
  Inactive: 'inactive',
  Pending: 'pending',
  Ready: 'ready',
  Error: 'error',
} as const

export type ExportJobState = (typeof ExportJobState)[keyof typeof ExportJobState]
