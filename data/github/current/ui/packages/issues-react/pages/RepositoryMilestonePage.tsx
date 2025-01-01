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
import {RepositoryMilestoneInternal} from '@github-ui/repository-milestone'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import type {RepositoryMilestonePageContentInternal$key} from './__generated__/RepositoryMilestonePageContentInternal.graphql'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import {useQueryContext} from '../contexts/QueryContext'
import {useEffect} from 'react'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../types/app-payload'
import type {UserSettingsOptionConfig} from '@github-ui/issue-create/getSafeConfig'

const PageQuery = graphql`
  query RepositoryMilestonePageQuery($name: String!, $owner: String!, $number: Int!, $first: Int!, $query: String!) {
    repository(owner: $owner, name: $name) {
      ...RepositoryMilestonePageContentInternal @arguments(first: $first, number: $number, query: $query)
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
      @argumentDefinitions(first: {type: "Int!"}, number: {type: "Int!"}, query: {type: "String!"}) {
        # eslint-disable-next-line relay/must-colocate-fragment-spreads
        ...RepositoryMilestoneInternal @arguments(first: $first, number: $number, query: $query)
      }
    `,
    repository,
  )

  const {current_user_settings} = useAppPayload<AppPayload>()

  const optionConfig: UserSettingsOptionConfig = {
    useMonospaceFont: current_user_settings.use_monospace_font,
    pasteUrlsAsPlainText: current_user_settings.paste_url_link_as_plain_text,
    singleKeyShortcutsEnabled: current_user_settings.use_single_key_shortcut,
  }

  return <RepositoryMilestoneInternal repository={data} optionConfig={optionConfig} />
}
