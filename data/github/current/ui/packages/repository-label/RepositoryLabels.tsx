import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {ThreePanesLayout} from '@github-ui/three-panes-layout'
import {Button, Heading} from '@primer/react'
import {graphql, useFragment} from 'react-relay'
import {LabelList} from './LabelList'
import {SearchBar} from './LabelSearchBar'
import {LabelCreate} from './LabelCreate'
import styles from './RepositoryLabel.module.css'
import type {RepositoryLabelsInternal$key} from './__generated__/RepositoryLabelsInternal.graphql'
import {useState} from 'react'

type RepositoryLabelsInternalProps = {
  repository: RepositoryLabelsInternal$key
}

export function RepositoryLabelsInternal({repository}: RepositoryLabelsInternalProps) {
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)

  const data = useFragment(
    graphql`
      fragment RepositoryLabelsInternal on Repository
      @argumentDefinitions(
        first: {type: "Int!", defaultValue: 30}
        orderField: {type: "LabelOrderField", defaultValue: NAME}
        orderDirection: {type: "OrderDirection", defaultValue: ASC}
        skip: {type: "Int!"}
        query: {type: "String"}
      ) {
        ...LabelList
          @arguments(
            first: $first
            orderField: $orderField
            orderDirection: $orderDirection
            skip: $skip
            query: $query
          )
        ...LabelCreate
        viewerCanPush
      }
    `,
    repository,
  )

  return (
    <>
      <ThreePanesLayout
        contentAs="div"
        resizeable={false}
        leftPaneWidth="small"
        middlePane={
          <div className={styles.middlePaneWrapper}>
            <div className={styles.header}>
              <Heading as="h2" className={styles.heading}>
                Labels
              </Heading>
              {data.viewerCanPush && (
                <Button variant="primary" onClick={() => setIsCreateDialogOpen(true)}>
                  New label
                </Button>
              )}
            </div>
            <SearchBar />
            <ErrorBoundary fallback={<div>Oops we could not load the labels</div>}>
              <LabelList repositoryRef={data} onCreateLabel={() => setIsCreateDialogOpen(true)} />
            </ErrorBoundary>
          </div>
        }
      />
      <LabelCreate repository={data} isOpen={isCreateDialogOpen} onClose={() => setIsCreateDialogOpen(false)} />
    </>
  )
}
