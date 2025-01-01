import type {GetChartResponse} from '../../../client/api/insights/contracts'
import type {
  GetItemsTrackedByParentResponse,
  GetMemexItemResponse,
  GetSuggestedAssigneesResponse,
  GetSuggestedIssueTypesResponse,
  GetSuggestedLabelsResponse,
  GetSuggestedMilestonesResponse,
  MemexItem,
  SuggestedAssignee,
  SuggestedIssueType,
  SuggestedLabel,
  SuggestedMilestone,
  UpdateMemexItemResponse,
} from '../../../client/api/memex-items/contracts'
import type {GetPaginatedItemsRequest, GetPaginatedItemsResponse} from '../../../client/api/memex-items/paginated-views'
import {
  AFTER_PARAM,
  FIRST_PARAM,
  HORIZONTAL_GROUPED_BY_COLUMN_KEY,
  HORIZONTAL_GROUPED_BY_COLUMN_VALUE_KEY,
  Q_PARAM,
  SECONDARY_AFTER_PARAM,
  SLICE_BY_COLUMN_ID_KEY,
  SUM_FIELDS_PARAM,
  VERTICAL_GROUPED_BY_COLUMN_KEY,
  VERTICAL_GROUPED_BY_COLUMN_VALUE_KEY,
} from '../../../client/platform/url'
import type {GetRequestType} from '../../../mocks/msw-responders'
import {
  get_getChart,
  get_getItemsTrackedByParent,
  get_getMemexItem,
  get_getPaginatedItems,
  get_getSuggestedAssigneesForMemexItem,
  get_getSuggestedIssueTypesForMemexItem,
  get_getSuggestedLabelsForMemexItem,
  get_getSuggestedMilestonesForMemexItem,
  put_updateMemexItem,
} from '../../../mocks/msw-responders/memex-items'
import {mswServer} from '../../msw-server'
import {stubApiMethod, stubApiMethodForMultipleResponses, stubApiMethodWithError} from './stub-api-method'

export function stubGetItem(memexProjectItem: MemexItem) {
  return stubApiMethod<GetRequestType, GetMemexItemResponse>(get_getMemexItem, {
    memexProjectItem,
  })
}

export function stubGetSuggestedAssignees(suggestions: Array<SuggestedAssignee>) {
  return stubApiMethod<GetRequestType, GetSuggestedAssigneesResponse>(get_getSuggestedAssigneesForMemexItem, {
    suggestions,
  })
}

export function stubGetSuggestedAssigneesWithError(error: Error) {
  return stubApiMethodWithError<GetRequestType, GetSuggestedAssigneesResponse>(
    get_getSuggestedAssigneesForMemexItem,
    error,
  )
}

export function stubGetSuggestedLabels(suggestions: Array<SuggestedLabel>) {
  return stubApiMethod<GetRequestType, GetSuggestedLabelsResponse>(get_getSuggestedLabelsForMemexItem, {
    suggestions,
  })
}

export function stubGetSuggestedLabelsWithError(error: Error) {
  return stubApiMethodWithError<GetRequestType, GetSuggestedLabelsResponse>(get_getSuggestedLabelsForMemexItem, error)
}

export function stubGetSuggestedMilestones(suggestions: Array<SuggestedMilestone>) {
  return stubApiMethod<GetRequestType, GetSuggestedMilestonesResponse>(get_getSuggestedMilestonesForMemexItem, {
    suggestions,
  })
}

export function stubGetSuggestedIssueTypes(suggestions: Array<SuggestedIssueType>) {
  return stubApiMethod<GetRequestType, GetSuggestedIssueTypesResponse>(get_getSuggestedIssueTypesForMemexItem, {
    suggestions,
  })
}

export function stubGetSuggestedIssueTypesWithError(error: Error) {
  return stubApiMethodWithError<GetRequestType, GetSuggestedIssueTypesResponse>(
    get_getSuggestedIssueTypesForMemexItem,
    error,
  )
}

export function stubGetSuggestedMilestonesWithError(error: Error) {
  return stubApiMethodWithError<GetRequestType, GetSuggestedMilestonesResponse>(
    get_getSuggestedMilestonesForMemexItem,
    error,
  )
}

export function stubGetItemsTrackedByParent(response: GetItemsTrackedByParentResponse) {
  return stubApiMethod<GetRequestType, GetItemsTrackedByParentResponse>(get_getItemsTrackedByParent, response)
}

export function stubGetPaginatedItems(response: GetPaginatedItemsResponse) {
  return stubApiMethod<GetRequestType, GetPaginatedItemsResponse>(get_getPaginatedItems, response)
}

export function stubGetChartRequest(response: GetChartResponse) {
  return stubApiMethod<GetRequestType, GetChartResponse>(get_getChart, response)
}

export function stubGetPaginatedItemsForMultipleResponses(responses: Array<GetPaginatedItemsResponse>) {
  return stubApiMethodForMultipleResponses<GetRequestType, GetPaginatedItemsResponse>(get_getPaginatedItems, responses)
}

export function stubUpdateItem(response: UpdateMemexItemResponse) {
  return stubApiMethod<GetRequestType, UpdateMemexItemResponse>(put_updateMemexItem, response)
}

export function stubGetPaginatedItemsMethodAndCaptureQueryParameters(response: GetPaginatedItemsResponse) {
  const stub = jest.fn<GetPaginatedItemsResponse, [URLSearchParams]>()
  const handler = get_getPaginatedItems((body, req) => {
    const url = new URL(req.url)
    stub(url.searchParams)
    return Promise.resolve(response)
  })
  mswServer.use(handler)
  return stub
}

export function expectRequestToHaveBeenCalledWithQueryParams(
  stub: jest.Mock<GetPaginatedItemsResponse, [URLSearchParams]>,
  request: GetPaginatedItemsRequest,
) {
  expect(stub).toHaveBeenCalledTimes(1)
  const queryParams = stub.mock.calls[0][0]

  let queryParamCount = 0
  for (const queryParam of queryParams.keys()) {
    queryParamCount++
    if (queryParam === Q_PARAM) {
      expect(queryParams.get(queryParam)).toEqual(request.q)
    } else if (queryParam === AFTER_PARAM) {
      expect(queryParams.get(queryParam)).toEqual(request.after)
    } else if (queryParam === SECONDARY_AFTER_PARAM) {
      expect(queryParams.get(queryParam)).toEqual(request.secondaryAfter)
    } else if (queryParam === FIRST_PARAM) {
      expect(queryParams.get(queryParam)).toEqual(request.first?.toString())
    } else if (queryParam === SLICE_BY_COLUMN_ID_KEY) {
      expect(queryParams.get(queryParam)).toEqual(request.sliceByColumnId?.toString())
    } else if (queryParam === VERTICAL_GROUPED_BY_COLUMN_KEY) {
      expect(queryParams.get(queryParam)).toEqual(request.verticalGroupedByColumnId?.toString())
    } else if (queryParam === VERTICAL_GROUPED_BY_COLUMN_VALUE_KEY) {
      expect(queryParams.get(queryParam)).toEqual(request.verticalGroupedByGroupValue)
    } else if (queryParam === HORIZONTAL_GROUPED_BY_COLUMN_KEY) {
      expect(queryParams.get(queryParam)).toEqual(request.horizontalGroupedByColumnId?.toString())
    } else if (queryParam === HORIZONTAL_GROUPED_BY_COLUMN_VALUE_KEY) {
      expect(queryParams.get(queryParam)).toEqual(request.groupedByGroupValue)
    } else if (queryParam === SUM_FIELDS_PARAM) {
      expect(queryParams.get(queryParam)).toEqual(JSON.stringify(request.sumFields))
    } else {
      throw new Error(`Encountered unexpected query param key ${queryParam}`)
    }
  }

  // Ensure that there weren't any keys in the expected request that
  // we didn't have a query parameter for
  expect(queryParamCount).toEqual(Object.keys(request).length)
}
