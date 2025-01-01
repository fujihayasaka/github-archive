import {useMemo} from 'react'
import {
  AutofixValidationCheckStatus,
  AutofixValidationType,
  type AutofixValidationCheck,
} from '../types/autofix-validation-check'
import {CheckCircleIcon, ClockIcon, XCircleIcon} from '@primer/octicons-react'
import {assertNeverWithoutThrowing} from '../utils/assert-never'

export type AutofixValidationCheckItemProps = {
  validationCheck: AutofixValidationCheck
}

export function AutofixValidationCheckItem({validationCheck}: AutofixValidationCheckItemProps) {
  const statusIcon = useMemo(() => {
    switch (validationCheck.status) {
      case AutofixValidationCheckStatus.Success:
        return <CheckCircleIcon className="color-fg-open" />
      case AutofixValidationCheckStatus.Failed:
        return <XCircleIcon className="color-fg-danger" />
      case AutofixValidationCheckStatus.Pending:
        return <ClockIcon className="color-fg-muted" />
      default:
        assertNeverWithoutThrowing(validationCheck.status)
    }
  }, [validationCheck.status])
  const statusText = useMemo(() => {
    switch (validationCheck.status) {
      case AutofixValidationCheckStatus.Success:
        return 'Passing'
      case AutofixValidationCheckStatus.Failed:
        return 'Failing'
      case AutofixValidationCheckStatus.Pending:
        return 'Waiting for'
      default:
        assertNeverWithoutThrowing(validationCheck.status)
    }
  }, [validationCheck.status])
  const typeText = useMemo(() => {
    switch (validationCheck.validationType) {
      case AutofixValidationType.Llm:
        return 'LLM evaluation'
      case AutofixValidationType.CodeQL:
        return 'CodeQL analysis'
      case AutofixValidationType.Linter:
        return 'linter check'
      case AutofixValidationType.Tests:
        return 'tests'
      default:
        assertNeverWithoutThrowing(validationCheck.validationType)
    }
  }, [validationCheck.validationType])

  return (
    <>
      {statusIcon}{' '}
      <span className="ml-1">
        {statusText} {typeText}
      </span>
    </>
  )
}
