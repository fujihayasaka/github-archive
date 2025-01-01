import {useCallback} from 'react'
import {useFragment, useRelayEnvironment} from 'react-relay'
import {graphql} from 'relay-runtime'
import type {ToggleMilestoneState$key} from './__generated__/ToggleMilestoneState.graphql'
import {commitUpdateMilestoneMutation} from './mutations/update-milestone-mutation'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {Button} from '@primer/react'

export function ToggleMilestoneState({milestoneRef}: {milestoneRef: ToggleMilestoneState$key}) {
  const data = useFragment(
    graphql`
      fragment ToggleMilestoneState on Milestone {
        id
        closed
      }
    `,
    milestoneRef,
  )
  const environment = useRelayEnvironment()
  const {addToast} = useToastContext()

  const onClick = useCallback(() => {
    // Logic to toggle the milestone state
    commitUpdateMilestoneMutation({
      environment,
      input: {id: data.id, state: data.closed ? 'OPEN' : 'CLOSED'},
      onCompleted: () => {},
      onError: () => {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: 'Could not change Milestone status',
        })
      },
    })
  }, [addToast, data.closed, data.id, environment])

  return (
    <Button onClick={onClick} variant={'default'}>
      {data.closed ? 'Reopen Milestone' : 'Close Milestone'}
    </Button>
  )
}
