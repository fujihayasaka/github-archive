import {
  graphql,
  useFragment,
  usePreloadedQuery,
  type EntryPointComponent,
  type PreloadedQuery,
  type UseQueryLoaderLoadQueryOptions,
} from 'react-relay'
import {useQueryContext} from '../contexts/QueryContext'
import {useEffect} from 'react'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import type {
  RepositoryLabelIndexPageQuery,
  RepositoryLabelIndexPageQuery$variables,
} from './__generated__/RepositoryLabelIndexPageQuery.graphql'
import {AnalyticsWrapper} from './AnalyticsWrapper'
import {useEntryPointsLoader} from '../hooks/use-entrypoint-loaders'
import {RepositoryLabelsInternal} from '@github-ui/repository-label/RepositoryLabels'
import type {RepositoryLabelIndexPageContentInternal$key} from './__generated__/RepositoryLabelIndexPageContentInternal.graphql'

const PageQuery = graphql`
  query RepositoryLabelIndexPageQuery(
    $name: String!
    $owner: String!
    $first: Int!
    $orderField: LabelOrderField = NAME
    $orderDirection: OrderDirection = ASC
    $skip: Int!
    $query: String
  ) {
    repository(owner: $owner, name: $name) {
      ...RepositoryLabelIndexPageContentInternal
        @arguments(first: $first, orderField: $orderField, orderDirection: $orderDirection, skip: $skip, query: $query)
    }
  }
`

export const RepositoryLabelIndexPage: EntryPointComponent<
  {pageQuery: RepositoryLabelIndexPageQuery},
  Record<string, never>
> = ({queries: {pageQuery}}) => {
  const {queryRef, loadQuery} = useEntryPointsLoader(pageQuery, PageQuery)
  if (!queryRef) return null
  return (
    <AnalyticsWrapper category="Repository Label Index">
      <RepositoryLabelIndexContent pageQueryRef={queryRef} loadQuery={loadQuery} />
    </AnalyticsWrapper>
  )
}

function RepositoryLabelIndexContent({
  pageQueryRef,
}: {
  pageQueryRef: PreloadedQuery<RepositoryLabelIndexPageQuery>
  loadQuery: (
    variables: RepositoryLabelIndexPageQuery$variables,
    options?: UseQueryLoaderLoadQueryOptions | undefined,
  ) => void
}) {
  const pageData = usePreloadedQuery<RepositoryLabelIndexPageQuery>(PageQuery, pageQueryRef)

  const {setCurrentViewId} = useQueryContext()
  useEffect(() => {
    setCurrentViewId(VIEW_IDS.repository)
  }, [pageQueryRef, setCurrentViewId])

  if (!pageData.repository) {
    reportError(
      new Error(`Could not find repository when loading labels index for ${ssrSafeLocation?.href.toString()}`),
    )
    return <div>Repository not found</div>
  }
  return <RepositoryLabelIndexPageContentInternal repository={pageData.repository} />
}

function RepositoryLabelIndexPageContentInternal({
  repository,
}: {
  repository: RepositoryLabelIndexPageContentInternal$key
}) {
  const data = useFragment(
    graphql`
      fragment RepositoryLabelIndexPageContentInternal on Repository
      @argumentDefinitions(
        first: {type: "Int!"}
        orderField: {type: "LabelOrderField", defaultValue: NAME}
        orderDirection: {type: "OrderDirection", defaultValue: ASC}
        skip: {type: "Int!"}
        query: {type: "String"}
      ) {
        ...RepositoryLabelsInternal
          @arguments(
            first: $first
            orderField: $orderField
            orderDirection: $orderDirection
            skip: $skip
            query: $query
          )
      }
    `,
    repository,
  )
  return <RepositoryLabelsInternal repository={data} />
}
