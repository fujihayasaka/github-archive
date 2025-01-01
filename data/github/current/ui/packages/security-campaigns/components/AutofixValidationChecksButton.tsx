import {useMemo, useState} from 'react'
import {AnchoredOverlay, Button} from '@primer/react'
import {CheckCircleIcon, ClockIcon, StopIcon} from '@primer/octicons-react'
import {AutofixValidationCheckStatus, type AutofixValidationCheck} from '../types/autofix-validation-check'
import {AutofixValidationChecksOverlayContent} from './AutofixValidationChecksOverlayContent'
import type {Repository} from '../types/repository'

export type AutofixValidationChecksButtonProps = {
  validationChecks: AutofixValidationCheck[]
  repository: Repository
}

export function AutofixValidationChecksButton({validationChecks, repository}: AutofixValidationChecksButtonProps) {
  const [open, setOpen] = useState(false)

  const passingValidationChecks = useMemo(() => {
    return validationChecks.filter(check => check.status === AutofixValidationCheckStatus.Success)
  }, [validationChecks])

  const leadingVisual = useMemo(() => {
    const isPartiallyPassing = validationChecks.some(
      validationCheck => validationCheck.status === AutofixValidationCheckStatus.Success,
    )
    const isPartiallyPending = validationChecks.some(
      validationCheck => validationCheck.status === AutofixValidationCheckStatus.Pending,
    )

    if (isPartiallyPassing) {
      return <CheckCircleIcon className="color-fg-success" />
    }
    if (isPartiallyPending) {
      return <ClockIcon className="color-fg-muted" />
    }
    return <StopIcon />
  }, [validationChecks])

  if (validationChecks.length === 0) {
    return null
  }

  return (
    <AnchoredOverlay
      open={open}
      onOpen={() => setOpen(true)}
      onClose={() => setOpen(false)}
      renderAnchor={props => (
        <Button
          variant="invisible"
          leadingVisual={leadingVisual}
          aria-label={`${passingValidationChecks.length} of ${validationChecks.length} autofix validation checks are passing`}
          {...props}
        >
          {passingValidationChecks.length}/{validationChecks.length}
        </Button>
      )}
      side="outside-top"
      width="medium"
    >
      <AutofixValidationChecksOverlayContent validationChecks={validationChecks} repository={repository} />
    </AnchoredOverlay>
  )
}
