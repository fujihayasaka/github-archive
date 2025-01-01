import type {Direction} from '@primer/behaviors'
import {type FocusZoneHookSettings, useFocusZone} from '@primer/react'
import {useCallback, useEffect, useRef} from 'react'

import {MARKER_NAV_KEYS} from '../constants/navigation-keys'
import type {GenericMarkerNavEl} from '../helpers/marker-navigator'
import {MarkerNavigator} from '../helpers/marker-navigator'
import type {DiffAnnotation, ThreadSummary} from '../types'

/**
 * Hook that provides keyboard navigation functionality for inline markers
 *
 * Uses arrow keys to navigate between markers
 */
export function useMarkerNavigation({
  containerRef,
  markers,
  disabled = false,
  focusInStrategy = 'previous',
  selectedMarkerId,
}: {
  containerRef: React.RefObject<HTMLElement>
  markers: Array<ThreadSummary | GenericMarkerNavEl | DiffAnnotation>
  // onMarkerSelected: (markerId: string) => void
  disabled?: boolean
  focusInStrategy?: FocusZoneHookSettings['focusInStrategy']
  selectedMarkerId?: string | null
}) {
  const prevMarkerNavigator = useRef<MarkerNavigator | undefined>(undefined)
  const markerNavigator = useRef<MarkerNavigator | undefined>(undefined)

  // Create a new marker navigator or use the previous one's state if available
  // Store the current navigator for the next render
  // Needs to be in a effect since MarkerNavigator queries the DOM
  useEffect(() => {
    markerNavigator.current = new MarkerNavigator(
      markers,
      prevMarkerNavigator.current?.focusedMarker?.id || selectedMarkerId || undefined,
    )
    prevMarkerNavigator.current = markerNavigator.current
  }, [markers, selectedMarkerId])

  // Handle keyboard navigation between markers, comments, and elements within.
  const getNextFocusable = useCallback(
    (_direction: Direction, from: Element | undefined, event: KeyboardEvent) => {
      const currentElement = from as HTMLElement

      // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
      const key = event.key

      const isNotMarkerOrComment =
        !currentElement?.hasAttribute('data-marker-id') &&
        !currentElement?.hasAttribute('data-marker-navigation-comment-id')

      switch (true) {
        // Handle when the currently focused element is an element within marker or comment.
        case isNotMarkerOrComment &&
          (key === 'ArrowUp' || key === 'ArrowDown' || key === 'ArrowRight' || key === 'ArrowLeft'): {
          return (
            currentElement?.closest<HTMLElement>('[data-marker-navigation-comment-id]') ||
            currentElement?.closest<HTMLElement>('[data-marker-id]') ||
            undefined
          )
        }
        case key === 'ArrowUp' || key === 'ArrowDown': {
          {
            if (markerNavigator.current && currentElement?.hasAttribute('data-marker-id')) {
              const nextMarker = markerNavigator.current.moveToNextMarker(key, from)
              if (nextMarker) {
                return document.querySelector<HTMLElement>(`[data-marker-id="${nextMarker.id}"]`) || undefined
              }
              return currentElement
            }
            if (markerNavigator.current && currentElement?.hasAttribute('data-marker-navigation-comment-id')) {
              const nextMarkerItem = markerNavigator.current.moveToNextMarkerItem(key, from)
              if (nextMarkerItem) {
                return (
                  document.querySelector<HTMLElement>(`[data-marker-navigation-comment-id="${nextMarkerItem.id}"]`) ||
                  undefined
                )
              }
              return currentElement
            }
          }
          return currentElement
        }
        case key === 'ArrowRight': {
          const currentElementIsThreadComment = currentElement?.hasAttribute('data-marker-navigation-comment-id')

          if (currentElementIsThreadComment) return currentElement

          if (currentElement?.hasAttribute('data-marker-id')) {
            return currentElement?.querySelector<HTMLElement>('[data-first-thread-comment="true"]') || undefined
          }

          return currentElement
        }
        case key === 'ArrowLeft': {
          const currentElementIsThread = currentElement?.hasAttribute('data-marker-id')

          if (currentElementIsThread) return currentElement

          if (currentElement?.hasAttribute('data-marker-navigation-comment-id')) {
            return currentElement?.closest<HTMLElement>('[data-marker-id]') || undefined
          }

          return currentElement
        }
        default: {
          return currentElement ?? undefined
        }
      }
    },
    [markerNavigator],
  )

  // Set up focus zone for keyboard navigation
  useFocusZone(
    {
      containerRef,
      bindKeys: MARKER_NAV_KEYS,
      getNextFocusable,
      focusableElementFilter: element =>
        element.hasAttribute('data-marker-id') || element.hasAttribute('data-marker-navigation-comment-id'),
      focusInStrategy,
      disabled,
    },
    [getNextFocusable, disabled],
  )

  return {markerNavigator}
}
