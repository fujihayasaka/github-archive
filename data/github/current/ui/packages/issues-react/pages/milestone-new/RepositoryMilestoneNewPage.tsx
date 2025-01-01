import {useEffect} from 'react'
import {graphql, useFragment, usePreloadedQuery, type EntryPointComponent, type PreloadedQuery} from 'react-relay'
import {useEntryPointsLoader} from '../../hooks/use-entrypoint-loaders'
import {AnalyticsWrapper} from '../AnalyticsWrapper'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useQueryContext} from '../../contexts/QueryContext'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import {MilestoneCreate} from '@github-ui/repository-milestone/MilestoneCreate'

import type {RepositoryMilestoneNewPageQuery} from './__generated__/RepositoryMilestoneNewPageQuery.graphql'
import type {RepositoryMilestoneNewPageContentInternal$key} from './__generated__/RepositoryMilestoneNewPageContentInternal.graphql'
import type {UserSettingsOptionConfig} from '@github-ui/issue-create/getSafeConfig'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../../types/app-payload'

const PageQuery = graphql`
  query RepositoryMilestoneNewPageQuery($name: String!, $owner: String!) {
    repository(owner: $owner, name: $name) {
      ...RepositoryMilestoneNewPageContentInternal
    }
  }
`

export const RepositoryMilestoneNewPage: EntryPointComponent<
  {pageQuery: RepositoryMilestoneNewPageQuery},
  Record<string, never>
> = ({queries: {pageQuery}}) => {
  const {queryRef} = useEntryPointsLoader(pageQuery, PageQuery)
  if (!queryRef) return null

  return (
    <AnalyticsWrapper category="Repository Milestone New">
      <RepositoryMilestoneNewPageContent pageQueryRef={queryRef} />
    </AnalyticsWrapper>
  )
}

function RepositoryMilestoneNewPageContent({
  pageQueryRef,
}: {
  pageQueryRef: PreloadedQuery<RepositoryMilestoneNewPageQuery>
}) {
  const pageData = usePreloadedQuery<RepositoryMilestoneNewPageQuery>(PageQuery, pageQueryRef)

  const {setCurrentViewId} = useQueryContext()
  useEffect(() => {
    setCurrentViewId(VIEW_IDS.repository)
  }, [pageQueryRef, setCurrentViewId])

  if (!pageData.repository) {
    reportError(
      new Error(`Could not find repository when loading milestone new page for ${ssrSafeLocation?.href.toString()}`),
    )
    return <div>Repository not found</div>
  }
  return <RepositoryMilestoneNewPageContentInternal repository={pageData.repository} />
}

function RepositoryMilestoneNewPageContentInternal({
  repository,
}: {
  repository: RepositoryMilestoneNewPageContentInternal$key
}) {
  const data = useFragment(
    graphql`
      fragment RepositoryMilestoneNewPageContentInternal on Repository {
        ...MilestoneCreateFormRepositoryQuery
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

  return <MilestoneCreate repository={data} optionConfig={optionConfig} />
}
