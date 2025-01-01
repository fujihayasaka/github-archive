import {Dialog} from '@primer/react'
import {destroyRoleAssignmentPath} from '@github-ui/paths'
import {useMutation} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useBannerContext} from '../BannerProvider'
import {ActorType, type ActorBasicMeta} from '../types/ActorRoleAssignment'

export function RoleDetailsRowRemoveDialog({
  actor,
  roleId,
  roleName,
  setOpen,
  returnFocusRef,
}: {
  actor: ActorBasicMeta
  roleId: number
  roleName: string
  setOpen: (open: boolean) => void
  returnFocusRef?: React.RefObject<HTMLButtonElement>
}) {
  const {navigate, showBanner} = useBannerContext()

  const {mutate, isPending} = useMutation({
    mutationFn: async () => {
      const response = await verifiedFetchJSON(
        destroyRoleAssignmentPath({
          path: actor.roleAssignmentsPath,
          actorId: actor.id,
          actorType: actor.type,
          roleId,
        }),
        {
          method: 'DELETE',
        },
      )

      // Potential expected errors, handled in onSuccess callback
      if (response.status === 403 || response.status === 422) {
        return await response.json()
      }

      if (!response.ok) {
        throw new Error(response.statusText)
      }

      return await response.json()
    },
    onError: () => {
      showBanner({
        message: 'Something went wrong while removing the role assignment. Please try again later.',
        variant: 'critical',
      })
      setOpen(false)
    },
    onSuccess: data => {
      if (data.success) {
        navigate(
          window.location.pathname,
          {replace: true},
          {
            message: data.message || 'Role assignment removed successfully.',
            variant: 'success',
          },
        )
        setOpen(false)
      } else {
        showBanner({
          message: data.error || 'Something went wrong while removing the role assignment. Please try again later.',
          variant: 'critical',
        })
        setOpen(false)
      }
    },
  })

  return (
    <Dialog
      title="Remove role assignment"
      onClose={() => setOpen(false)}
      returnFocusRef={returnFocusRef}
      width="large"
      footerButtons={[
        {content: 'Cancel', onClick: () => setOpen(false)},
        {
          content: 'Remove',
          buttonType: 'danger',
          disabled: isPending,
          loading: isPending,
          onClick: () => mutate(),
        },
      ]}
    >
      You&apos;re about to remove the assignment of the <b>{roleName}</b> role from{' '}
      <span>
        {actor.type === ActorType.EnterpriseTeam ? (
          <>
            the <b>{actor.name}</b> enterprise team
          </>
        ) : (
          <b>{actor.name}</b>
        )}
      </span>
      .
    </Dialog>
  )
}
