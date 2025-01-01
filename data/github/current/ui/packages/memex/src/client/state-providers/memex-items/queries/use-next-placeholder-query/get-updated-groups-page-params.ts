import type {QueryClient} from '@tanstack/react-query'

import type {
  PaginatedGroups,
  PaginatedGroupsAndSecondaryGroupsData,
  PaginatedGroupsData,
} from '../../../../api/memex-items/paginated-views'
import {
  getQueryDataForMemexGroupsPage,
  getQueryDataForMemexSecondaryGroupsPage,
  setQueryDataForMemexGroupsPage,
  setQueryDataForMemexSecondaryGroupsPage,
} from '../../query-client-api/memex-groups'
import {nextPlaceholderPageInfo} from '../../query-client-api/page-params'
import {
  buildMemexGroupsQueryKey,
  buildMemexSecondaryGroupsQueryKey,
  type PageTypeForGroups,
  pageTypeForGroups,
  type PageTypeForSecondaryGroups,
} from '../query-keys'
import {
  type MemexGroupsPageQueryData,
  type PageParam,
  pageParamForInitialPage,
  pageParamForNextPlaceholder,
  type PaginatedMemexItemsQueryVariables,
  type WithoutTotal,
} from '../types'

export const getUpdatedGroupsPageParams = (
  queryClient: QueryClient,
  variables: PaginatedMemexItemsQueryVariables,
  pageParams: Array<PageParam> = [],
  pageType: PageTypeForGroups | PageTypeForSecondaryGroups,
  newData: PaginatedGroups,
): Array<PageParam> => {
  if (pageParams.length === 0 || pageParams[0] !== pageParamForInitialPage) {
    // A grouped response will include the initial page of secondary groups
    // If the pageParams arg doesn't contain a "pageParamForInitialPage", then we can
    // infer that we're dealing with secondary groups, and we should seed the initial page param.
    pageParams.unshift(pageParamForInitialPage)
  }
  if (pageParams[pageParams.length - 1] !== pageParamForNextPlaceholder) {
    // Nothing else to handle, we can return early
    return pageParams
  }
  // We have some data in the `next_placeholder` query, so lets update the data, and potentially
  // add a new query for the next page.
  const currentNextPlaceholderData =
    pageType === pageTypeForGroups
      ? getQueryDataForMemexGroupsPage(queryClient, variables, pageParamForNextPlaceholder)
      : getQueryDataForMemexSecondaryGroupsPage(queryClient, variables, pageParamForNextPlaceholder)
  const pageParamsWithoutNextPlaceholder = pageParams.slice(0, pageParams.length - 1)
  const newNextPlaceholderDataGroups = currentNextPlaceholderData?.groups.slice(newData.nodes.length)
  if (newNextPlaceholderDataGroups?.length && newData.pageInfo.hasNextPage && newData.pageInfo.endCursor) {
    const newNextPlaceholderData: MemexGroupsPageQueryData = {
      groups: newNextPlaceholderDataGroups,
      pageInfo: nextPlaceholderPageInfo,
    }
    const newPageParams: Array<PageParam> = [
      ...pageParamsWithoutNextPlaceholder,
      {after: newData.pageInfo.endCursor},
      pageParamForNextPlaceholder,
    ]

    // Set query data for the next placeholder page
    if (pageType === pageTypeForGroups) {
      setQueryDataForMemexGroupsPage(queryClient, variables, pageParamForNextPlaceholder, newNextPlaceholderData)
    } else {
      setQueryDataForMemexSecondaryGroupsPage(
        queryClient,
        variables,
        pageParamForNextPlaceholder,
        newNextPlaceholderData,
      )
    }
    return newPageParams
  } else {
    // We have no more data in the next placeholder query, so let's remove it.
    if (pageType === pageTypeForGroups) {
      queryClient.removeQueries({
        queryKey: buildMemexGroupsQueryKey(variables, pageParamForNextPlaceholder),
      })
    } else {
      queryClient.removeQueries({
        queryKey: buildMemexSecondaryGroupsQueryKey(variables, pageParamForNextPlaceholder),
      })
    }
    return pageParamsWithoutNextPlaceholder
  }
}

/*
 * Check whether the response contains net new groups for a given page type.
 *
 * When paginating primary groups, the client ignores secondary groups in responses
 * as they will be duplicates of the secondary groups in the initial primary groups response.
 *
 * When paginating secondary groups, the client ignores primary groups in responses
 * as they will be duplicates of the primary groups in the initial secondary groups response.
 *
 * The client can infer that groups for one pageType are new if groups for the
 * inverse pageType has pageInfo.hasPreviousPage: false.
 */
export const responseContainsNewGroups = (
  pageType: PageTypeForGroups | PageTypeForSecondaryGroups,
  response: WithoutTotal<PaginatedGroupsData> | WithoutTotal<PaginatedGroupsAndSecondaryGroupsData>,
) => {
  const inverseGroupType = pageType === pageTypeForGroups ? response.secondaryGroups : response.groups
  const isInitialPageOfInverseGroups = !inverseGroupType?.pageInfo.hasPreviousPage
  return isInitialPageOfInverseGroups
}
