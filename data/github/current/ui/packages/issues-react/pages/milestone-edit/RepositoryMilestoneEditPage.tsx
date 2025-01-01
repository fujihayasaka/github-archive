import {useEffect} from 'react'
import {graphql, useFragment, usePreloadedQuery, type EntryPointComponent, type PreloadedQuery} from 'react-relay'
import {useEntryPointsLoader} from '../../hooks/use-entrypoint-loaders'
import {AnalyticsWrapper} from '../AnalyticsWrapper'
import {ssrSafeLocation} from '@github-ui/ssr-utils'
import {useQueryContext} from '../../contexts/QueryContext'
import {VIEW_IDS} from '@github-ui/issue-url-helper/constants/view-constants'
import {MilestoneEdit} from '@github-ui/repository-milestone/MilestoneEdit'

import type {UserSettingsOptionConfig} from '@github-ui/issue-create/getSafeConfig'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type {AppPayload} from '../../types/app-payload'
import type {RepositoryMilestoneEditPageQuery} from './__generated__/RepositoryMilestoneEditPageQuery.graphql'
import type {RepositoryMilestoneEditPageContentInternal$key} from './__generated__/RepositoryMilestoneEditPageContentInternal.graphql'

const PageQuery = graphql`
  query RepositoryMilestoneEditPageQuery($name: String!, $owner: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      ...RepositoryMilestoneEditPageContentInternal @arguments(number: $number)
    }
  }
`

export const RepositoryMilestoneEditPage: EntryPointComponent<
  {pageQuery: RepositoryMilestoneEditPageQuery},
  Record<string, never>
> = ({queries: {pageQuery}}) => {
  const {queryRef} = useEntryPointsLoader(pageQuery, PageQuery)
  if (!queryRef) return null

  return (
    <AnalyticsWrapper category="Repository Milestone Edit">
      <RepositoryMilestoneEditPageContent pageQueryRef={queryRef} />
    </AnalyticsWrapper>
  )
}

function RepositoryMilestoneEditPageContent({
  pageQueryRef,
}: {
  pageQueryRef: PreloadedQuery<RepositoryMilestoneEditPageQuery>
}) {
  const pageData = usePreloadedQuery<RepositoryMilestoneEditPageQuery>(PageQuery, pageQueryRef)

  const {setCurrentViewId} = useQueryContext()
  useEffect(() => {
    setCurrentViewId(VIEW_IDS.repository)
  }, [pageQueryRef, setCurrentViewId])

  if (!pageData.repository) {
    reportError(
      new Error(`Could not find repository when loading milestone edit page for ${ssrSafeLocation?.href.toString()}`),
    )
    return <div>Repository not found</div>
  }
  return <RepositoryMilestoneEditPageContentInternal repository={pageData.repository} />
}

function RepositoryMilestoneEditPageContentInternal({
  repository,
}: {
  repository: RepositoryMilestoneEditPageContentInternal$key
}) {
  const data = useFragment(
    graphql`
      fragment RepositoryMilestoneEditPageContentInternal on Repository @argumentDefinitions(number: {type: "Int!"}) {
        ...MilestoneEditFormRepositoryQuery @arguments(number: $number)
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

  return <MilestoneEdit repository={data} optionConfig={optionConfig} />
}
