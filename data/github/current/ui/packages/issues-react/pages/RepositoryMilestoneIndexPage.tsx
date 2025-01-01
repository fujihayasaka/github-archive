import {
  graphql,
  useFragment,
  usePreloadedQuery,
  type EntryPointComponent,
  type PreloadedQuery,
  type UseQueryLoaderLoadQueryOptions,
} from 'react-relay'
import {useEntryPointsLoader} from '../hooks/use-entrypoint-loaders'
import {AnalyticsWrapper} from './AnalyticsWrapper'

import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import {useQueryContext} from '../contexts/QueryContext'
import {useEffect} from 'react'
import type {
  RepositoryMilestoneIndexPageQuery,
  RepositoryMilestoneIndexPageQuery$variables,
} from './__generated__/RepositoryMilestoneIndexPageQuery.graphql'
import type {RepositoryMilestoneIndexPageContentInternal$key} from './__generated__/RepositoryMilestoneIndexPageContentInternal.graphql'
import {RepositoryMilestonesInternal} from '@github-ui/repository-milestone/RepositoryMilestones'

const PageQuery = graphql`
  query RepositoryMilestoneIndexPageQuery(
    $name: String!
    $owner: String!
    $state: MilestoneState!
    $orderField: MilestoneOrderField = CREATED_AT
    $orderDirection: OrderDirection = DESC
  ) {
    repository(owner: $owner, name: $name) {
      ...RepositoryMilestoneIndexPageContentInternal
        @arguments(state: $state, orderField: $orderField, orderDirection: $orderDirection)
    }
  }
`

export const RepositoryMilestoneIndexPage: EntryPointComponent<
  {pageQuery: RepositoryMilestoneIndexPageQuery},
  Record<string, never>
> = ({queries: {pageQuery}}) => {
  const {queryRef, loadQuery} = useEntryPointsLoader(pageQuery, PageQuery)
  if (!queryRef) return null

  return (
    <AnalyticsWrapper category="Repository Milestone Index">
      <RepositoryMilestoneIndexContent pageQueryRef={queryRef} loadQuery={loadQuery} />
    </AnalyticsWrapper>
  )
}

function RepositoryMilestoneIndexContent({
  pageQueryRef,
}: {
  pageQueryRef: PreloadedQuery<RepositoryMilestoneIndexPageQuery>
  loadQuery: (
    variables: RepositoryMilestoneIndexPageQuery$variables,
    options?: UseQueryLoaderLoadQueryOptions | undefined,
  ) => void
}) {
  const pageData = usePreloadedQuery<RepositoryMilestoneIndexPageQuery>(PageQuery, pageQueryRef)

  const {setCurrentViewId} = useQueryContext()
  useEffect(() => {
    setCurrentViewId(VIEW_IDS.repository)
  }, [pageQueryRef, setCurrentViewId])

  if (!pageData.repository) {
    reportError(
      new Error(`Could not find repository when loading milestone index for ${ssrSafeLocation?.href.toString()}`),
    )
    return <div>Repository not found</div>
  }
  return <RepositoryMilestoneIndexPageContentInternal repository={pageData.repository} />
}

function RepositoryMilestoneIndexPageContentInternal({
  repository,
}: {
  repository: RepositoryMilestoneIndexPageContentInternal$key
}) {
  const data = useFragment(
    graphql`
      fragment RepositoryMilestoneIndexPageContentInternal on Repository
      @argumentDefinitions(
        state: {type: "MilestoneState!"}
        orderField: {type: "MilestoneOrderField", defaultValue: CREATED_AT}
        orderDirection: {type: "OrderDirection", defaultValue: DESC}
      ) {
        ...RepositoryMilestonesInternal
          @arguments(state: $state, orderField: $orderField, orderDirection: $orderDirection)
      }
    `,
    repository,
  )

  return <RepositoryMilestonesInternal repository={data} />
}
