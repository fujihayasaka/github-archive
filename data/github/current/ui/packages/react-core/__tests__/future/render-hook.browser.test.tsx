// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {describe, expect, it} from '@github-ui/tests'
import {useMatches} from 'react-router-dom'

import {renderHook} from '../../future/test-utils/Render'

function useMyHook() {
  return useMatches()
}

describe('RenderHook', () => {
  it('renders a hook inside the necessary providers', () => {
    const {result, router} = renderHook(useMyHook, '/')

    expect(router.state.location).toEqual(
      expect.objectContaining({
        pathname: '/',
      }),
    )

    expect(result.current).toEqual([
      expect.objectContaining({
        id: '__DATA_ROUTER_ROOT__',
        pathname: '/',
      }),
      expect.objectContaining({
        id: '__DATA_ROUTER_APPLICATION_ROUTES__',
        pathname: '/',
      }),
      expect.objectContaining({
        id: '__DATA_ROUTER_RENDER_HOOK_TEST_ROUTE__',
        pathname: '/',
      }),
    ])
  })
})
