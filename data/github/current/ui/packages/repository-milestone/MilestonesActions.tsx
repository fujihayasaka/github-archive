import {Button, Heading} from '@primer/react'
import {useFragment} from 'react-relay'
import {graphql} from 'relay-runtime'
import {LABELS} from './constants/labels'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import type {MilestonesActions$key} from './__generated__/MilestonesActions.graphql'
import styles from './RepositoryMilestone.module.css'
import {useNavigate} from '@github-ui/use-navigate'
import {useCallback} from 'react'

type MilestonesActionsProps = {
  repositoryRef: MilestonesActions$key
}

export function MilestonesActions({repositoryRef}: MilestonesActionsProps) {
  const {viewerCanPush, nameWithOwner} = useFragment(
    graphql`
      fragment MilestonesActions on Repository {
        viewerCanPush
        nameWithOwner
      }
    `,
    repositoryRef,
  )

  const rootUrl = `${ssrSafeLocation.origin}/${nameWithOwner}`
  const newMilestoneUrl = `${rootUrl}/milestones/new`
  const navigate = useNavigate()

  const showNewMilestoneDialog = useCallback(() => {
    navigate(newMilestoneUrl)
  }, [navigate, newMilestoneUrl])

  return (
    <div className={styles.buttonGrp}>
      <Heading as="h2" className={styles.heading}>
        Milestones
      </Heading>

      {viewerCanPush ? (
        <div className={styles.actionsGrp}>
          <Button
            as="a"
            href={newMilestoneUrl}
            onClick={showNewMilestoneDialog}
            variant="primary"
            data-testid="new-milestone-button"
          >
            {LABELS.newMilestone}
          </Button>
        </div>
      ) : null}
    </div>
  )
}
