// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'

import {BlackbirdPermissionCaches} from '../blackbird-warm-caches'

class TestPermissionCaches extends BlackbirdPermissionCaches {
  testWarmCaches() {
    return this.warmCaches()
  }

  reset() {
    TestPermissionCaches.warmCachesLoopSetup = false
  }
}

describe('BlackbirdPermissionCaches', () => {
  describe('#warmCaches', () => {
    it('sends request to warm caches', async () => {
      jest.useFakeTimers()
      jest.spyOn(global, 'setTimeout')
      mockFetch.mockRouteOnce('/search/warm_blackbird_caches', {userCacheExpiresAt: Date.now() + 31000})

      const service = new TestPermissionCaches()
      service.reset()
      await service.testWarmCaches()

      expect(setTimeout).toHaveBeenCalledTimes(1)
      expect(setTimeout).toHaveBeenLastCalledWith(expect.any(Function), 1000)
    })

    it('defaults to 30s', async () => {
      jest.useFakeTimers()
      jest.spyOn(global, 'setTimeout')
      mockFetch.mockRouteOnce('/search/warm_blackbird_caches', {})

      const service = new TestPermissionCaches()
      service.reset()
      await service.testWarmCaches()

      expect(setTimeout).toHaveBeenCalledTimes(1)
      expect(setTimeout).toHaveBeenLastCalledWith(expect.any(Function), 30000)
    })
  })
})
