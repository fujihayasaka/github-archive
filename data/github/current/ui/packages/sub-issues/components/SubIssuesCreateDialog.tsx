import {graphql, useFragment} from 'react-relay'
import {CreateIssueDialogEntry, type CreateIssueDialogEntryProps} from '@github-ui/issue-create/CreateIssueDialogEntry'
import type {SubIssuesCreateDialog$key} from './__generated__/SubIssuesCreateDialog.graphql'
import {noop} from '@github-ui/noop'
import {useAlert} from '../utils/use-alert'
import {useCallback} from 'react'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../types/app-payload'
import {RelationshipsAlertDialog} from '@github-ui/issue-viewer/RelationshipsAlertDialog'

export function SubIssuesCreateDialog({
  issue,
  open,
  setOpen,
  onCreateSuccess,
}: {
  issue: SubIssuesCreateDialog$key
  open: boolean
  setOpen: (open: boolean) => void
  onCreateSuccess: CreateIssueDialogEntryProps['onCreateSuccess']
}) {
  const {alert, resetAlert, showServerAlert} = useAlert()
  const appPayload = useAppPayload<AppPayload>()
  const data = useFragment(
    // !! NOTE: This fragment is preloaded on the server via the primary IssueViewer query, so the data
    // here is loaded whether the flag is enabled or not. Please be careful and don't include fields which
    // are not already loaded by other fragments.
    graphql`
      fragment SubIssuesCreateDialog on Issue {
        id
        repository {
          id
          name
          owner {
            login
          }
        }
      }
    `,
    issue,
  )

  const onCreateError = useCallback((error: Error) => showServerAlert(error), [showServerAlert])
  const issueCreateProps: CreateIssueDialogEntryProps = {
    navigate: noop,
    onCreateSuccess,
    onCreateError,
    isCreateDialogOpen: open,
    setIsCreateDialogOpen: setOpen,
    optionConfig: {
      useMonospaceFont: appPayload?.current_user_settings?.use_monospace_font ?? false,
      scopedOrganization: data.repository.owner.login,
      issueCreateArguments: {
        repository: {
          owner: data.repository.owner.login,
          name: data.repository.name,
        },
        parentIssue: {
          id: data.id,
        },
      },
    },
  }

  return (
    <>
      {alert && (
        <RelationshipsAlertDialog title={alert.title} onClose={resetAlert}>
          {alert.body}
        </RelationshipsAlertDialog>
      )}
      <CreateIssueDialogEntry {...issueCreateProps} />
    </>
  )
}
