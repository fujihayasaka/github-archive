import {useEnabledFeatures} from './use-enabled-features'
import {useMemexRootHeight} from './use-memex-root-height'

/** Returns whether or not the roadmap table should be narrow (i.e., condensed) */
export function useRoadmapTableIsNarrow(): {isTableNarrow: boolean} {
  const {clientWidth} = useMemexRootHeight()
  const {memex_small_viewport_a11y} = useEnabledFeatures()
  const viewportWidth = clientWidth ?? 0

  if (!memex_small_viewport_a11y) {
    return {isTableNarrow: false}
  }

  // 544px = "small" breakpoint size in Primer
  return {isTableNarrow: viewportWidth < 544}
}
