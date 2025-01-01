import {useRelayEnvironment} from 'react-relay'
import {Resources} from '../constants/strings'
import {commitUpdateIssueTypeMutation} from '../mutations/update-issue-type-mutation'
import {useCallback} from 'react'
import {formatError} from '../utils'
import {useIssueTypesMutationErrorsContext} from '../contexts/IssueTypesMutationErrorsContext'

export const useEnableDisableIssueType = () => {
  const environment = useRelayEnvironment()
  const {setMutationError, clearError} = useIssueTypesMutationErrorsContext()

  const updateIssueType = useCallback(
    (issueTypeId: string, isEnabled: boolean, onDone?: () => void) => {
      clearError()
      commitUpdateIssueTypeMutation({
        environment,
        input: {
          issueTypeId,
          isEnabled,
        },
        onError: () => {
          const errorMessage = isEnabled ? Resources.enabledIssueTypeError : Resources.disabledIssueTypeError
          setMutationError(errorMessage)
          onDone?.()
        },
        onCompleted: response => {
          const errors = response.updateIssueType?.errors || []
          if (errors.length > 0) {
            errors.map((e: {message: string}) => reportError(formatError('UpdateIssueType', e.message)))
            const errorMessage = isEnabled ? Resources.enabledIssueTypeError : Resources.disabledIssueTypeError
            setMutationError(errorMessage)
          }
          onDone?.()
        },
      })
    },
    [environment, setMutationError, clearError],
  )

  const enableOrganizationIssueType = (issueTypeId: string, onDone?: () => void) => {
    updateIssueType(issueTypeId, true, onDone)
  }

  const disableOrganizationIssueType = (issueTypeId: string, onDone?: () => void) => {
    updateIssueType(issueTypeId, false, onDone)
  }

  return {
    enableOrganizationIssueType,
    disableOrganizationIssueType,
  }
}
