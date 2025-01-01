import {testIdProps} from '@github-ui/test-id-props'
import {XIcon} from '@primer/octicons-react'
import {destroyRoleAssignmentPath} from '@github-ui/paths'
import {Dialog, IconButton, Text} from '@primer/react'
import {useMutation} from '@github-ui/react-query'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {useState, useRef} from 'react'
import {useBannerContext} from '../BannerProvider'
import {ActorType, type Actor, type RoleAssignment} from '../types/ActorRoleAssignment'
import {createAssignmentSourcesList, getIndirectAssignmentSourceElements} from '../utils/AssignmentSourcesUtils'

interface DeleteResponse {
  success: boolean
  error?: string
  message?: string
}

export function RemoveRoleAssignmentButton({actor, roleAssignment}: {actor: Actor; roleAssignment: RoleAssignment}) {
  const [isOpen, setOpen] = useState(false)
  const [isSubmitting, setSubmitting] = useState(false)
  const {showBanner, navigate} = useBannerContext()

  const buttonRef = useRef<HTMLButtonElement>(null)

  const {mutate} = useMutation<DeleteResponse>({
    mutationFn: async () => {
      const path = window.location.pathname

      const response = await verifiedFetch(
        destroyRoleAssignmentPath({
          path,
          actorId: actor.id,
          actorType: actor.type,
          roleId: roleAssignment.role.id,
        }),
        {
          method: 'DELETE',
        },
      )
      if (response.ok || response.status === 422) {
        return await response.json()
      }

      throw new Error(`Unexpected status ${response.status}`)
    },
    onError: () => {
      showBanner({
        message: 'Something went wrong while removing the role assignment. Please try again later.',
        variant: 'critical',
      })
      setOpen(false)
      setSubmitting(false)
    },
    onSuccess: (data: DeleteResponse) => {
      if (data.success) {
        const message =
          data.message ??
          `The ${roleAssignment.role.name} role was removed from ${
            actor.type === ActorType.User ? actor.name : `the ${actor.name} team`
          }.`
        navigate(window.location.pathname, {replace: true}, {message, variant: 'success'})
        setOpen(false)
        setSubmitting(false)
      } else {
        showBanner({
          message: 'Something went wrong while removing the role assignment. Please try again later.',
          variant: 'critical',
        })
        setOpen(false)
        setSubmitting(false)
      }
    },
  })

  let actorText: JSX.Element
  switch (actor.type) {
    case ActorType.EnterpriseTeam:
      actorText = (
        <span>
          the <Text weight="semibold">{actor.name}</Text> enterprise team
        </span>
      )
      break
    default:
      actorText = <Text weight="semibold">{actor.name}</Text>
  }

  let sources: Array<string | JSX.Element> = []
  if (roleAssignment.indirect_assignments.length > 0) {
    const indirectAssignmentSources = getIndirectAssignmentSourceElements(
      roleAssignment.role.id,
      roleAssignment.indirect_assignments,
      false,
    )

    sources = createAssignmentSourcesList(indirectAssignmentSources)
    sources.push(indirectAssignmentSources.length > 1 ? ' teams' : ' team')
  }

  return (
    <>
      {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
      <IconButton
        ref={buttonRef}
        icon={XIcon}
        variant="invisible"
        aria-label="Remove role assignment"
        onClick={() => setOpen(!isOpen)}
        unsafeDisableTooltip
        {...testIdProps('remove-assignment-button')}
      />
      {isOpen && (
        <Dialog
          title="Remove role assignment"
          onClose={() => setOpen(false)}
          returnFocusRef={buttonRef}
          width="large"
          footerButtons={[
            {content: 'Cancel', onClick: () => setOpen(false)},
            {
              content: 'Remove',
              buttonType: 'danger',
              disabled: isSubmitting,
              loading: isSubmitting,
              onClick: () => {
                setSubmitting(true)
                mutate()
              },
            },
          ]}
        >
          You&apos;re about to remove the direct assignment of the{' '}
          <Text weight="semibold">{roleAssignment.role.name}</Text> role from {actorText}.
          {sources.length > 0 && <span> However, this role will still be assigned through the {sources}.</span>}
        </Dialog>
      )}
    </>
  )
}
