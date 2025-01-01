export type AutofixValidationCheck = {
  validationType: AutofixValidationType
  status: AutofixValidationCheckStatus
  workflowRunId: string
}

export const AutofixValidationType = {
  Llm: 'llm',
  CodeQL: 'codeql',
  Linter: 'linter',
  Tests: 'tests',
} as const

export type AutofixValidationType = (typeof AutofixValidationType)[keyof typeof AutofixValidationType]

export const AutofixValidationCheckStatus = {
  Pending: 'pending',
  Success: 'success',
  Failed: 'failed',
} as const

export type AutofixValidationCheckStatus =
  (typeof AutofixValidationCheckStatus)[keyof typeof AutofixValidationCheckStatus]
