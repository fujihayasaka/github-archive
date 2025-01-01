import {Dialog} from '@primer/react'
import {useMutation} from '@github-ui/react-query'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {useBannerContext} from '../BannerProvider'
import {ActorType, type ActorBasicMeta, type IndirectRoleAssignmentSource} from '../types/ActorRoleAssignment'
import {createAssignmentSourcesList, getIndirectAssignmentSourceElements} from '../utils/AssignmentSourcesUtils'
import {useRoutingContext} from '../contexts/RoutingProvider'

// Create a default value for indirect assignments to guarantee same reference for props comparison
const DEFAULT_INDIRECT_ASSIGNMENTS: IndirectRoleAssignmentSource[] = []

export function RemoveRoleAssignmentDialog({
  actor,
  roleId,
  roleName,
  indirectAssignments = DEFAULT_INDIRECT_ASSIGNMENTS,
  setOpen,
  returnFocusRef,
  canViewEnterpriseTeams,
}: {
  actor: ActorBasicMeta
  roleId: number
  roleName: string
  indirectAssignments?: IndirectRoleAssignmentSource[]
  setOpen: (open: boolean) => void
  returnFocusRef?: React.RefObject<HTMLButtonElement>
  canViewEnterpriseTeams: boolean
}) {
  const {navigate, showBanner} = useBannerContext()
  const {destroyRoleAssignmentPath} = useRoutingContext()

  const {mutate, isPending} = useMutation({
    mutationFn: async () => {
      const response = await verifiedFetchJSON(
        destroyRoleAssignmentPath({actorId: actor.id, actorType: actor.type, roleId}),
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
        const params = new URLSearchParams(window.location.search)
        params.delete('page')
        const query = params.toString()
        const pathname = `${window.location.pathname}${query ? `?${query}` : ''}`
        navigate(
          pathname,
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

  let actorDisplay
  switch (actor.type) {
    case ActorType.EnterpriseTeam:
      actorDisplay = (
        <>
          the <b>{actor.name}</b> enterprise team
        </>
      )
      break
    case ActorType.Team:
      actorDisplay = (
        <>
          the <b>{actor.name}</b> team
        </>
      )
      break
    default:
      actorDisplay = <b>{actor.name}</b>
  }

  let sources: Array<string | JSX.Element> = []
  if (indirectAssignments.length > 0) {
    const indirectAssignmentSources = getIndirectAssignmentSourceElements(
      roleId,
      indirectAssignments,
      false,
      canViewEnterpriseTeams,
    )

    sources = createAssignmentSourcesList(indirectAssignmentSources)
    sources.push(indirectAssignmentSources.length > 1 ? ' teams' : ' team')
  }

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
      You&apos;re about to remove the direct assignment of the <b>{roleName}</b> role from {actorDisplay}.
      {sources.length > 0 && <span> However, this role will still be assigned through the {sources}.</span>}
    </Dialog>
  )
}
