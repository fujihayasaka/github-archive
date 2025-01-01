import type {EntryPointComponent} from 'react-relay'

import {useEntryPointsLoader} from '../../hooks/use-entrypoint-loaders'
import {AnalyticsWrapper} from '../AnalyticsWrapper'
import type {InternalIssueNewPageUrlArgumentsMetadataQuery} from './__generated__/InternalIssueNewPageUrlArgumentsMetadataQuery.graphql'
import {InternalIssueNewPageUrlArgumentsMetadata, InternalIssueNewPageWithUrlParams} from './InternalIssueNewPage'

export const IssueRepoNewPage: EntryPointComponent<
  {
    pageQuery: InternalIssueNewPageUrlArgumentsMetadataQuery
  },
  Record<string, never>
> = ({queries: {pageQuery}}) => {
  const {queryRef: urlArgumentsMetadataQueryRef} = useEntryPointsLoader(
    pageQuery,
    InternalIssueNewPageUrlArgumentsMetadata,
  )
  if (!urlArgumentsMetadataQueryRef) return null

  return (
    <AnalyticsWrapper category="Repository Issue Create">
      <InternalIssueNewPageWithUrlParams urlParameterQueryData={urlArgumentsMetadataQueryRef} />
    </AnalyticsWrapper>
  )
}
