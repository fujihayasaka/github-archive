import {getApiMetadata} from '../../helpers/api-metadata'
import {fetchJSON} from '../../platform/functional-fetch-wrapper'
import {
  AFTER_PARAM,
  BEFORE_PARAM,
  FIELD_IDS_PARAM,
  FIRST_PARAM,
  HORIZONTAL_GROUPED_BY_COLUMN_KEY,
  HORIZONTAL_GROUPED_BY_COLUMN_VALUE_KEY,
  Q_PARAM,
  SCOPE_PARAM,
  SECONDARY_AFTER_PARAM,
  SLICE_BY_COLUMN_ID_KEY,
  SLICE_VALUE_KEY,
  SORTED_BY_COLUMN_DIRECTION_KEY,
  SORTED_BY_COLUMN_ID_KEY,
  VERTICAL_GROUPED_BY_COLUMN_KEY,
  VERTICAL_GROUPED_BY_COLUMN_VALUE_KEY,
  VIEW_TYPE_PARAM,
} from '../../platform/url'
import type {GetPaginatedItemsRequest, GetPaginatedItemsResponse} from './paginated-views'

export async function apiGetPaginatedItems(
  request: GetPaginatedItemsRequest = {},
  signal?: AbortSignal,
): Promise<GetPaginatedItemsResponse> {
  const apiData = getApiMetadata('memex-paginated-items-get-api-data')
  const url = new URL(apiData.url, window.location.origin)
  if (request.after) {
    url.searchParams.set(AFTER_PARAM, request.after)
  }
  if (request.secondaryAfter) {
    url.searchParams.set(SECONDARY_AFTER_PARAM, request.secondaryAfter)
  }
  if (request.before) {
    url.searchParams.set(BEFORE_PARAM, request.before)
  }
  if (request.first) {
    url.searchParams.set(FIRST_PARAM, request.first.toString())
  }
  if (request.q) {
    url.searchParams.set(Q_PARAM, request.q)
  }
  if (request.scope) {
    url.searchParams.set(SCOPE_PARAM, request.scope)
  }
  if (request.sortedBy) {
    for (const {columnId, direction} of request.sortedBy) {
      url.searchParams.append(SORTED_BY_COLUMN_DIRECTION_KEY, direction)
      url.searchParams.append(SORTED_BY_COLUMN_ID_KEY, `${columnId}`)
    }
  }
  if (request.horizontalGroupedByColumnId != null) {
    url.searchParams.set(HORIZONTAL_GROUPED_BY_COLUMN_KEY, `${request.horizontalGroupedByColumnId}`)
  }
  if (request.verticalGroupedByColumnId != null) {
    url.searchParams.set(VERTICAL_GROUPED_BY_COLUMN_KEY, `${request.verticalGroupedByColumnId}`)
  }
  if (request.groupedByGroupValue) {
    url.searchParams.set(HORIZONTAL_GROUPED_BY_COLUMN_VALUE_KEY, `${request.groupedByGroupValue}`)
  }
  if (request.verticalGroupedByGroupValue) {
    url.searchParams.set(VERTICAL_GROUPED_BY_COLUMN_VALUE_KEY, `${request.verticalGroupedByGroupValue}`)
  }
  if (request.sliceByColumnId) {
    url.searchParams.set(SLICE_BY_COLUMN_ID_KEY, `${request.sliceByColumnId}`)
  }
  if (request.sliceByValue) {
    url.searchParams.set(SLICE_VALUE_KEY, `${request.sliceByValue}`)
  }
  if (request.fieldIds?.length) {
    url.searchParams.set(FIELD_IDS_PARAM, JSON.stringify(request.fieldIds))
  }
  if (request.viewType) {
    url.searchParams.set(VIEW_TYPE_PARAM, request.viewType)
  }
  if (request.sumFields) {
    url.searchParams.set('sumFields', JSON.stringify(request.sumFields))
  }
  const {data} = await fetchJSON<GetPaginatedItemsResponse>(url, {signal})

  return data
}
