import {isLoggedIn} from '@github-ui/client-env'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {getBaseFetchHeaders} from '@github-ui/fetch-headers'

export type WarmCachesResponse = {
  userCacheExpiresAt: string
}

export class BlackbirdPermissionCaches {
  protected static warmCachesLoopSetup = false
  protected static warmResolve: (value: void) => void
  protected static warm = new Promise<void>(resolve => {
    BlackbirdPermissionCaches.warmResolve = resolve
  })

  async setupWarmCachesLoop() {
    if (!isLoggedIn()) {
      return
    }
    if (!BlackbirdPermissionCaches.warmCachesLoopSetup) {
      BlackbirdPermissionCaches.warmCachesLoopSetup = true
      await this.warmCaches()
    } else {
      await BlackbirdPermissionCaches.warm
    }
  }

  async warmCaches() {
    let ttl = 9 * 60 * 1000 // 9 minutes
    try {
      // Warm blackbird's user ACL cache, making searches faster. It's OK to call repeatedly since it's a noop if the
      // caches are already warm.
      const resp = await verifiedFetchJSON('/search/warm_blackbird_caches', {
        headers: {Accept: 'application/json', ...getBaseFetchHeaders()},
      })
      const data = (await resp.json()) as WarmCachesResponse
      ttl = new Date(data.userCacheExpiresAt).getTime() - Date.now()
      ttl = ttl - 30 * 1000 // less 30 seconds so that we warm before it expires.
      if (isNaN(ttl) || ttl <= 5) {
        ttl = 30 * 1000
      }
    } catch {
      // no-op
    }
    BlackbirdPermissionCaches.warmResolve()
    setTimeout(() => {
      void this.warmCaches()
    }, ttl)
  }
}
