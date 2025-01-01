import {getApiMetadata} from '../../helpers/api-metadata'
import {getEnabledFeatures} from '../../helpers/feature-flags'
import {fetchJSONWith} from '../../platform/functional-fetch-wrapper'
import {EagerQueryInvalidationSingleton} from '../../state-providers/data-refresh/eager-query-invalidation'
import {mostRecentUpdateSingleton} from '../../state-providers/data-refresh/most-recent-update'
import {pendingUpdatesSingleton} from '../../state-providers/data-refresh/pending-updates'
import {type BulkUpdateMemexItemsRequest, type BulkUpdateMemexItemsResponse, REQUEST_ID_HEADER} from './contracts'

export async function apiBulkUpdateItems(body: BulkUpdateMemexItemsRequest): Promise<BulkUpdateMemexItemsResponse> {
  const {memex_table_without_limits, memex_sync_write_to_es} = getEnabledFeatures()

  pendingUpdatesSingleton.increment()

  try {
    const apiData = getApiMetadata('memex-item-update-bulk-api-data')
    const {headers: responseHeaders, data} = await fetchJSONWith<BulkUpdateMemexItemsResponse>(apiData.url, {
      method: 'PUT',
      body,
    })

    // find the most recent update amongst the bulk updates, and set it as the most recent update, defaulting to 0
    // in the odd case where the updatedAt field is not present
    let mostRecent = 0

    // memexProjectItems is optional now that this may run asynchonously in a background job
    if (data.memexProjectItems) {
      for (const item of data.memexProjectItems) {
        if (item.updatedAt) {
          mostRecent = Math.max(mostRecent, new Date(item.updatedAt).getTime())
        }
      }
    }

    mostRecentUpdateSingleton.set(mostRecent)
    pendingUpdatesSingleton.decrement()

    const requestId = responseHeaders.get(REQUEST_ID_HEADER) || undefined
    if (memex_table_without_limits && memex_sync_write_to_es && requestId) {
      EagerQueryInvalidationSingleton.register(requestId)
    }

    return {requestId, ...data}
  } catch (e) {
    pendingUpdatesSingleton.decrement()
    throw e
  }
}
