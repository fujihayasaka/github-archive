/*
 * For loading diff entries progressively, we have four available render modes:
 *
 * 1. RENDER - for diff entries that are already loaded, render right away
 * 2. EAGER_AUTO_LOAD - for unloaded entries, fetch and render as quickly as possible
 * 3. LAZY_AUTO_LOAD - for unloaded entries, wait to fetch and render until scrolled into view
 * 4. HIDE - for unloaded entries, don't render at all (wait for an event that changes render mode, like scrolling into view)
 */
export type ProgressiveDiffEntryRenderMode = 'EAGER_AUTO_LOAD' | 'HIDE' | 'LAZY_AUTO_LOAD' | 'RENDER'

export const ProgressiveLoadingStatus = {
  Loaded: 'Loaded',
  Loading: 'Loading',
  NotLoaded: 'NotLoaded',
} as const

export type ProgressiveLoadingStatusType = (typeof ProgressiveLoadingStatus)[keyof typeof ProgressiveLoadingStatus]

export type ProgressiveDiffEntry = {
  path: string
  pathDigest: string
  renderMode: ProgressiveDiffEntryRenderMode
  loadingStatus: ProgressiveLoadingStatusType
  loadSolo: boolean
}
