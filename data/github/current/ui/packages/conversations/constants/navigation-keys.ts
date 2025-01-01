import type {FocusMovementKeys} from '@primer/behaviors'
import {FocusKeys} from '@primer/behaviors'

// Define the key combination masks for marker navigation
export const MARKER_NAV_KEYS = FocusKeys.ArrowAll

// Map keys to their bit representations for quick lookups
export const KEY_TO_BIT: Record<string, number> = {
  ArrowLeft: FocusKeys.ArrowHorizontal,
  ArrowDown: FocusKeys.ArrowVertical,
  ArrowUp: FocusKeys.ArrowVertical,
  ArrowRight: FocusKeys.ArrowHorizontal,
} as {[k in FocusMovementKeys]: FocusKeys}
