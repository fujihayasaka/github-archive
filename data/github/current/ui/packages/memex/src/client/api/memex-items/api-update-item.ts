import {getApiMetadata} from '../../helpers/api-metadata'
import {fetchJSONWith} from '../../platform/functional-fetch-wrapper'
import {EagerQueryInvalidationSingleton} from '../../state-providers/data-refresh/eager-query-invalidation'
import {mostRecentUpdateSingleton} from '../../state-providers/data-refresh/most-recent-update'
import {pendingUpdatesSingleton} from '../../state-providers/data-refresh/pending-updates'
import {type IUpdateMemexItemRequest, REQUEST_ID_HEADER, type UpdateMemexItemResponse} from './contracts'

export async function apiUpdateItem(body: IUpdateMemexItemRequest): Promise<UpdateMemexItemResponse> {
  const apiData = getApiMetadata('memex-item-update-api-data')

  pendingUpdatesSingleton.increment()
  try {
    const {headers: responseHeaders, data} = await fetchJSONWith<UpdateMemexItemResponse>(apiData.url, {
      method: 'PUT',
      body,
    })
    // updatedAt should always be present after an update call, but we have to default it just in case, so default
    // it to a time that would always allow a live update
    mostRecentUpdateSingleton.set(new Date(data.memexProjectItem.updatedAt || 0).getTime())
    pendingUpdatesSingleton.decrement()

    const requestId = responseHeaders.get(REQUEST_ID_HEADER)
    if (data.invalidateQueryCache && requestId) {
      EagerQueryInvalidationSingleton.register(requestId)
    }

    return data
  } catch (e) {
    pendingUpdatesSingleton.decrement()
    throw e
  }
}
