import type {DiffAnnotation, ThreadSummary} from '../types'

interface MarkerPosition {
  markerId: string
  index: number
}

export interface GenericMarkerNavEl {
  id: string
}

type MarkerComments = Record<string, GenericMarkerNavEl[]>

/**
 * Helper class that manages navigation between thread and annotation markers
 */
export class MarkerNavigator {
  private markers: Array<ThreadSummary | GenericMarkerNavEl | DiffAnnotation>
  private markerComments: MarkerComments | null = null
  private currentMarkerPosition: MarkerPosition | null = null
  private currentMarkerCommentPosition: MarkerPosition | null = null

  constructor(
    markers: Array<ThreadSummary | GenericMarkerNavEl | DiffAnnotation>,
    currentMarkerId?: string,
    currentMarkerCommentId?: string,
  ) {
    this.markers = markers.map(marker => {
      const id = marker.id
      return {
        ...marker,
        id,
      }
    })

    this.markerComments = markers.reduce((acc, marker) => {
      const commentElements = document.querySelectorAll(`[data-marker-navigation-comment-thread-id="${marker.id}"]`)
      if (commentElements) {
        const commentIds = Array.from(commentElements).map(el => {
          return {
            id: el.getAttribute('data-marker-navigation-comment-id'),
          } as GenericMarkerNavEl
        })
        return {...acc, [marker.id.toString()]: commentIds}
      }
      return acc
    }, {})

    // Set initial position if a marker ID is provided
    if (currentMarkerId && !currentMarkerCommentId) {
      const index = this.markers.findIndex(marker => marker.id.toString() === currentMarkerId.toString())
      if (index !== -1) {
        this.currentMarkerPosition = {
          markerId: currentMarkerId,
          index,
        }
      }
    }
  }

  /**
   * Focuses a specific marker by its ID
   */
  focusMarker(markerId: string): void {
    const index = this.markers.findIndex(marker => marker.id.toString() === markerId.toString())
    if (index !== -1) {
      this.currentMarkerPosition = {
        markerId,
        index,
      }
    }
  }

  /**
   * Gets the currently focused marker
   */
  get focusedMarker(): ThreadSummary | GenericMarkerNavEl | DiffAnnotation | undefined {
    if (!this.currentMarkerPosition) return
    return this.markers[this.currentMarkerPosition.index]
  }

  /**
   * Move to the first comment of a marker
   */
  moveToFirstComment(from: Element | undefined): GenericMarkerNavEl | undefined {
    if (this.markers.length === 0) return
    if (!from) return
  }

  /**
   * Move to the next marker based on the specified direction
   */
  moveToNextMarker(
    direction: string,
    from: Element | undefined,
  ): ThreadSummary | GenericMarkerNavEl | DiffAnnotation | undefined {
    if (this.markers.length === 0) return

    if (from) {
      const closestMarker = from.closest('[data-marker-id]')
      const markerId = closestMarker?.getAttribute('data-marker-id')
      if (markerId) {
        this.currentMarkerPosition = {
          markerId,
          index: this.markers.findIndex(marker => {
            return marker.id.toString() === markerId.toString()
          }),
        }
      }
    }

    // If no marker is currently focused, start with the first or last one
    if (!this.currentMarkerPosition) {
      const newIndex = direction === 'ArrowUp' ? this.markers.length - 1 : 0
      const newMarker = this.markers[newIndex]

      if (!newMarker) return

      this.currentMarkerPosition = {
        markerId: newMarker.id,
        index: newIndex,
      }
      return this.markers[newIndex]
    }

    // Calculate the next index based on direction
    let nextIndex: number

    const isFirstMarker = this.currentMarkerPosition.index === 0
    const isLastMarker = this.currentMarkerPosition.index === this.markers.length - 1

    switch (direction) {
      case 'ArrowDown':
        // If it's the last marker, return the current focused marker to avoid infinite navigation loop
        if (isLastMarker) return undefined
        nextIndex = (this.currentMarkerPosition.index + 1) % this.markers.length
        break
      case 'ArrowUp':
        // If it's the first marker, return the current focused marker to avoid infinite navigation loop
        if (isFirstMarker) return undefined
        nextIndex = (this.currentMarkerPosition.index - 1 + this.markers.length) % this.markers.length
        break
      default:
        return undefined
    }

    const nextMarker = this.markers[nextIndex]
    if (!nextMarker) return

    // Update current position and return the next marker
    this.currentMarkerPosition = {
      markerId: nextMarker.id,
      index: nextIndex,
    }

    return nextMarker
  }

  /**
   * Move to the next comment marker based on the specified direction
   */
  moveToNextMarkerItem(direction: string, from: Element | undefined): GenericMarkerNavEl | undefined {
    if (!from || !this.markerComments) return

    const markerElement = from.closest('[data-marker-id]')
    const markerId = markerElement?.getAttribute('data-marker-id')
    if (!markerElement || !markerId) return

    const markerItems = this.markerComments[markerId] || []
    if (markerItems.length === 0) return

    const currentCommentId = from.getAttribute('data-marker-navigation-comment-id')
    const newIndex = markerItems.findIndex(c => c.id === currentCommentId)
    if (newIndex === -1) return

    let nextIndex: number
    const isFirstComment = newIndex === 0
    const isLastComment = newIndex === markerItems.length - 1

    switch (direction) {
      case 'ArrowDown':
        if (isLastComment) return undefined
        nextIndex = newIndex + 1
        break
      case 'ArrowUp':
        if (isFirstComment) return undefined
        nextIndex = newIndex - 1
        break
      default:
        return undefined
    }

    const nextComment = markerItems[nextIndex]
    if (!nextComment) return

    this.currentMarkerCommentPosition = {
      markerId: nextComment.id,
      index: nextIndex,
    }
    return nextComment
  }
}
