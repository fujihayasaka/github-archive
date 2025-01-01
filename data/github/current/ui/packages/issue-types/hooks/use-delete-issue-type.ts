import {useCallback} from 'react'
import {useRelayEnvironment, ConnectionHandler} from 'react-relay'
import {Resources} from '../constants/strings'
import {commitDeleteIssueTypeMutation} from '../mutations/delete-issue-type-mutation'
import {formatError} from '../utils'
import {ssrSafeWindow} from '@github-ui/ssr-utils'
import {useIssueTypesMutationErrorsContext} from '../contexts/IssueTypesMutationErrorsContext'

export const useDeleteIssueType = () => {
  const environment = useRelayEnvironment()
  const {setMutationError, clearError} = useIssueTypesMutationErrorsContext()

  const deleteIssueType = useCallback(
    (issueTypeId: string, owner: string, organizationId?: string, onDone?: () => void, redirect = true) => {
      clearError()

      const connectionId = organizationId
        ? ConnectionHandler.getConnectionID(organizationId, 'Organization_issueTypes')
        : undefined

      commitDeleteIssueTypeMutation({
        environment,
        input: {issueTypeId},
        connectionId,
        onError: () => {
          setMutationError(Resources.deletedIssueTypeError)
          onDone?.()
        },
        onCompleted: response => {
          const errors = response.deleteIssueType?.errors || []
          if (errors.length === 0) {
            // eslint-disable-next-line react-hooks/react-compiler
            if (redirect && ssrSafeWindow) ssrSafeWindow.location.href = `/organizations/${owner}/settings/issue-types`
          } else {
            errors.map((e: {message: string}) => reportError(formatError('DeleteIssueType', e.message)))
            setMutationError(Resources.deletedIssueTypeError)
          }
          onDone?.()
        },
      })
    },
    [environment, setMutationError, clearError],
  )

  return {
    deleteIssueType,
  }
}
