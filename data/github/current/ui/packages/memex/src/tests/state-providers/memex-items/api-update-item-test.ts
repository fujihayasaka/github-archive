import {apiUpdateItem} from '../../../client/api/memex-items/api-update-item'
import {fetchJSONWith} from '../../../client/platform/functional-fetch-wrapper'
import {EagerQueryInvalidationSingleton} from '../../../client/state-providers/data-refresh/eager-query-invalidation'
import {DefaultOpenIssue} from '../../../mocks/memex-items'
import {stubResolvedApiResponse} from '../../mocks/api/memex'

jest.mock('../../../client/state-providers/data-refresh/eager-query-invalidation')
jest.mock('../../../client/platform/functional-fetch-wrapper')

describe('apiUpdateItem', () => {
  it('does not store request IDs by default', async () => {
    stubResolvedApiResponse(fetchJSONWith, {
      headers: new Headers({'X-GitHub-Request-Id': '123'}),
      ok: true,
      data: {memexProjectItem: DefaultOpenIssue},
    })

    await apiUpdateItem({
      memexProjectItemId: DefaultOpenIssue.id,
      fieldIds: [],
      layoutType: 'board',
      previousMemexProjectItemId: undefined,
    })

    expect(EagerQueryInvalidationSingleton.register).not.toHaveBeenCalled()
  })

  it('stores IDs for successful requests that indicate query cache invalidation', async () => {
    stubResolvedApiResponse(fetchJSONWith, {
      headers: new Headers({'X-GitHub-Request-Id': '123'}),
      ok: true,
      data: {memexProjectItem: DefaultOpenIssue, invalidateQueryCache: true},
    })

    await apiUpdateItem({
      memexProjectItemId: DefaultOpenIssue.id,
      fieldIds: [],
      layoutType: 'board',
      previousMemexProjectItemId: undefined,
    })

    expect(EagerQueryInvalidationSingleton.register).toHaveBeenCalledWith('123')
  })
})
