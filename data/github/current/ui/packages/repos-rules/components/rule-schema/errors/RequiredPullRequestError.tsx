import type {RegisteredRuleErrorComponent, ValidationError} from '../../../types/rules-types'
import {RulesetFormErrorFlash} from '../../RulesetFormErrorFlash'
import {useRegisterErrors, type ErrorFilterFunction} from '../../../hooks/use-register-errors'

const pullRequestErrorsFilter: Record<string, ErrorFilterFunction> = {
  // This function is used to indicate that the error is handled by the form control
  // We must register these so they don't show in the error component
  requiredReviewer: {
    args: 'error',
    func: (error: ValidationError) => {
      // Handle required reviewers error in the component
      if (error.field === 'required_reviewers') {
        return true
      }
      return false
    },
  },
}

export function RequiredPullRequestError({errors, errorId, errorRef, fields}: RegisteredRuleErrorComponent) {
  const parsedErrors = useRegisterErrors({errors, fields, filters: pullRequestErrorsFilter})
  let message: string | undefined = undefined
  if (parsedErrors.unregistered && parsedErrors.unregistered.length > 0) {
    message = parsedErrors.unregistered[0]?.message || 'An error occurred'
  }

  if (message) {
    return (
      <RulesetFormErrorFlash errorId={errorId} errorRef={errorRef}>
        {message}
      </RulesetFormErrorFlash>
    )
  }
  return null
}
