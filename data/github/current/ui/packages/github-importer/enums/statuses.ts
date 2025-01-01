export const Status = {
  Invalid: 'Invalid',
  Pending: 'Pending',
  InProgress: 'InProgress',
  Succeeded: 'Succeeded',
  Failed: 'Failed',
  FailedValidation: 'FailedValidation',
} as const

export type Status = (typeof Status)[keyof typeof Status]
