import {Label} from '@primer/react'
import {AutofixValidationCheckStatus, type AutofixValidationCheck} from '../types/autofix-validation-check'
import {useMemo} from 'react'

export type AutofixLabelProps = {
  validationChecks?: AutofixValidationCheck[]
}

export const AutofixLabel = ({validationChecks}: AutofixLabelProps) => {
  const isValidated = useMemo(() => {
    if (!validationChecks || validationChecks.length === 0) {
      return false
    }

    return validationChecks.every(check => check.status === AutofixValidationCheckStatus.Success)
  }, [validationChecks])

  if (!isValidated) {
    return <Label variant="default">Autofix</Label>
  }

  return <Label variant="success">Validated autofix</Label>
}
