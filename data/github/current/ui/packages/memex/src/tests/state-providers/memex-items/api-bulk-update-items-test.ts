import {apiBulkUpdateItems} from '../../../client/api/memex-items/api-bulk-update-items'
import {fetchJSONWith} from '../../../client/platform/functional-fetch-wrapper'
import {EagerQueryInvalidationSingleton} from '../../../client/state-providers/data-refresh/eager-query-invalidation'
import {createMockEnvironment} from '../../create-mock-environment'
import {stubResolvedApiResponse} from '../../mocks/api/memex'

jest.mock('../../../client/state-providers/data-refresh/eager-query-invalidation')
jest.mock('../../../client/platform/functional-fetch-wrapper')

describe('apiBulkUpdateItems', () => {
  it('does not store request IDs by default', async () => {
    createMockEnvironment({
      jsonIslandData: {
        'memex-enabled-features': [],
      },
    })

    stubResolvedApiResponse(fetchJSONWith, {
      headers: new Headers({'X-GitHub-Request-Id': '123'}),
      ok: true,
      data: {totalUpdatedItems: 0},
    })

    await apiBulkUpdateItems({
      memexProjectItems: [],
      fieldIds: [],
    })

    expect(EagerQueryInvalidationSingleton.register).not.toHaveBeenCalled()
  })

  it('stores IDs for successful requests when the necessary feature flags are enabled', async () => {
    createMockEnvironment({
      jsonIslandData: {
        'memex-enabled-features': ['memex_table_without_limits', 'memex_sync_write_to_es', 'memex_new_bulk_update_ux'],
      },
    })

    stubResolvedApiResponse(fetchJSONWith, {
      headers: new Headers({'X-GitHub-Request-Id': '123'}),
      ok: true,
      data: {totalUpdatedItems: 0},
    })

    await apiBulkUpdateItems({
      memexProjectItems: [],
      fieldIds: [],
    })

    expect(EagerQueryInvalidationSingleton.register).toHaveBeenCalledWith('123')
  })
})
