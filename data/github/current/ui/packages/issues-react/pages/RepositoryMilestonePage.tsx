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
import type {
  RepositoryMilestonePageQuery,
  RepositoryMilestonePageQuery$variables,
} from './__generated__/RepositoryMilestonePageQuery.graphql'
import {RepositoryMilestoneInternal as RepositoryMilestone} from '@github-ui/repository-milestone'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import type {RepositoryMilestonePageContentInternal$key} from './__generated__/RepositoryMilestonePageContentInternal.graphql'
import {VIEW_IDS} from '../constants/view-constants'
import {useQueryContext} from '../contexts/QueryContext'
import {useEffect} from 'react'

const PageQuery = graphql`
  query RepositoryMilestonePageQuery(
    $name: String!
    $owner: String!
    $number: Int!
    $first: Int!
    $states: [IssueState!]!
  ) {
    repository(owner: $owner, name: $name) {
      ...RepositoryMilestonePageContentInternal @arguments(first: $first, number: $number, states: $states)
    }
  }
`

export const RepositoryMilestonePage: EntryPointComponent<
  {pageQuery: RepositoryMilestonePageQuery},
  Record<string, never>
> = ({queries: {pageQuery}}) => {
  const {queryRef, loadQuery} = useEntryPointsLoader(pageQuery, PageQuery)
  if (!queryRef) return null

  return (
    <AnalyticsWrapper category="Repository Milestone Show">
      <RepositoryMilestoneContent pageQueryRef={queryRef} loadQuery={loadQuery} />
    </AnalyticsWrapper>
  )
}

export function RepositoryMilestoneContent({
  pageQueryRef,
}: {
  pageQueryRef: PreloadedQuery<RepositoryMilestonePageQuery>
  loadQuery: (
    variables: RepositoryMilestonePageQuery$variables,
    options?: UseQueryLoaderLoadQueryOptions | undefined,
  ) => void
}) {
  const pageData = usePreloadedQuery<RepositoryMilestonePageQuery>(PageQuery, pageQueryRef)

  const {setCurrentViewId} = useQueryContext()
  useEffect(() => {
    setCurrentViewId(VIEW_IDS.repository)
  }, [pageQueryRef, setCurrentViewId])

  if (!pageData.repository) {
    reportError(
      new Error(`Could not find repository when loading TemplateList for ${ssrSafeLocation?.href.toString()}`),
    )
    return <div>Repository not found</div>
  }
  return <RepositoryMilestonePageContentInternal repository={pageData.repository} />
}

function RepositoryMilestonePageContentInternal({
  repository,
}: {
  repository: RepositoryMilestonePageContentInternal$key
}) {
  const data = useFragment(
    graphql`
      fragment RepositoryMilestonePageContentInternal on Repository
      @argumentDefinitions(first: {type: "Int!"}, number: {type: "Int!"}, states: {type: "[IssueState!]!"}) {
        # eslint-disable-next-line relay/must-colocate-fragment-spreads
        ...RepositoryMilestone @arguments(first: $first, number: $number, states: $states)
        name
      }
    `,
    repository,
  )

  return (
    <div>
      <h1>Milestone in {data.name}</h1>
      <RepositoryMilestone repository={data} />
    </div>
  )
}
