import {graphql, useFragment} from 'react-relay'
import {ThreePanesLayout} from '@github-ui/three-panes-layout'
import styles from './RepositoryMilestone.module.css'
import {LABELS} from './constants/labels'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {MilestoneError} from './MilestoneError'
import type {RepositoryMilestonesInternal$key} from './__generated__/RepositoryMilestonesInternal.graphql'
import {MilestoneList} from './MilestoneList'
import {MilestonesActions} from './MilestonesActions'

type RepositoryMilestonesInternalProps = {
  repository: RepositoryMilestonesInternal$key
}

export function RepositoryMilestonesInternal({repository}: RepositoryMilestonesInternalProps) {
  const data = useFragment(
    graphql`
      fragment RepositoryMilestonesInternal on Repository
      @argumentDefinitions(
        state: {type: "MilestoneState!"}
        orderField: {type: "MilestoneOrderField", defaultValue: CREATED_AT}
        orderDirection: {type: "OrderDirection", defaultValue: DESC}
      ) {
        ...MilestoneList @arguments(state: $state, first: 50, orderField: $orderField, orderDirection: $orderDirection)
        ...MilestonesActions
      }
    `,
    repository,
  )

  return (
    <ThreePanesLayout
      contentAs="div"
      resizeable={false}
      leftPaneWidth="small"
      middlePane={
        <div className={styles.middlePaneWrapper}>
          <ErrorBoundary
            fallback={<MilestoneError title={LABELS.milestonesError} message={LABELS.milestonesErrorMessage} />}
          >
            <MilestonesActions repositoryRef={data} />
            <MilestoneList repositoryRef={data} />
          </ErrorBoundary>
        </div>
      }
    />
  )
}
