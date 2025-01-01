export function getAppPayload(enabled_features?: Record<string, boolean>) {
  return {
    helpUrl: 'https://help.github.com',
    refListCacheKey: 'v0:123',
    enabled_features,
  }
}
