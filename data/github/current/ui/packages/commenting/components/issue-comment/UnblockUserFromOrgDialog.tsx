import {ConfirmationDialog} from '@primer/react'
import {useCallback} from 'react'
import {useRelayEnvironment} from 'react-relay'
import {commitLocalUpdate} from 'relay-runtime'

import {unblockUserFromOrganization} from '../../mutations/unblock-user-from-organization-mutation'

export type UnblockUserFromOrgDialogProps = {
  organization: {login: string; id: string}
  contentAuthor: {login: string; id: string}
  onClose: () => void
  contentId: string
  /**
   * Callback function to handle the unblock action instead of Relay.
   * If provided, the dialog will be rendered without relay, allowing components outside of a relay environment to
   * use it.
   */
  onUnblock?: (organizationLogin: string, userLogin: string) => void
}

export const UnblockUserFromOrgDialog = (props: UnblockUserFromOrgDialogProps) => {
  return props.onUnblock ? (
    <UnblockUserFromOrgDialogWithoutRelay {...props} />
  ) : (
    <UnblockUserFromOrgDialogWithRelay {...props} />
  )
}

const UnblockUserFromOrgDialogWithRelay = ({
  contentAuthor,
  organization,
  onClose,
  contentId,
}: Omit<UnblockUserFromOrgDialogProps, 'onUnblock'>) => {
  const environment = useRelayEnvironment()

  const onDialogClose = useCallback(
    (gesture: 'confirm' | 'cancel' | 'close-button' | 'escape') => {
      if (gesture === 'confirm') {
        unblockUserFromOrganization({
          environment,
          input: {unblockedUserId: contentAuthor.id, organizationId: organization.id},
          onCompleted: () =>
            commitLocalUpdate(environment, store => {
              const contentObject = store.get(contentId)
              contentObject?.setValue(true, 'pendingUnblock')
              contentObject?.setValue(false, 'pendingBlock')
            }),
        })
      }
      onClose()
    },
    [onClose, environment, contentAuthor.id, organization.id, contentId],
  )

  return (
    <ConfirmationDialog
      title={`Unblock ${contentAuthor.login} from ${organization.login}`}
      confirmButtonContent={'Unblock user'}
      confirmButtonType="danger"
      onClose={onDialogClose}
    >
      Are you sure you want to unblock <strong>{contentAuthor.login}</strong> from <strong>{organization.login}</strong>
      ?
    </ConfirmationDialog>
  )
}

const UnblockUserFromOrgDialogWithoutRelay = ({
  contentAuthor,
  organization,
  onClose,
  onUnblock,
}: UnblockUserFromOrgDialogProps) => {
  const onDialogClose = useCallback(
    (gesture: 'confirm' | 'cancel' | 'close-button' | 'escape') => {
      if (gesture === 'confirm') {
        onUnblock?.(organization.login, contentAuthor.login)
      }
      onClose()
    },
    [onClose, onUnblock, organization.login, contentAuthor.login],
  )

  return (
    <ConfirmationDialog
      title={`Unblock ${contentAuthor.login} from ${organization.login}`}
      confirmButtonContent={'Unblock user'}
      confirmButtonType="danger"
      onClose={onDialogClose}
    >
      Are you sure you want to unblock <strong>{contentAuthor.login}</strong> from <strong>{organization.login}</strong>
      ?
    </ConfirmationDialog>
  )
}
