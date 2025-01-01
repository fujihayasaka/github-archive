import {CommentsPreference} from '@github-ui/diff-view-settings/page-data/payloads/diff-view-settings'
import {useEffect, useReducer, type Dispatch} from 'react'

type MarkersStatusAction =
  | 'SHOW_MARKERS'
  | 'USER_MINIMIZED_MARKERS'
  | 'USER_EXITED_MARKERS_DIALOG'
  | 'USER_EXPANDED_MARKERS'

type MarkersStatusState = {
  userMinimized: boolean
  showMarkers: boolean
}

function markersStatusReducer(state: MarkersStatusState, action: MarkersStatusAction) {
  switch (action) {
    case 'SHOW_MARKERS':
      return {
        userMinimized: false,
        showMarkers: true,
      }
    case 'USER_EXPANDED_MARKERS':
      return {
        showMarkers: true,
        userMinimized: false,
      }
    case 'USER_MINIMIZED_MARKERS':
      return {
        userMinimized: true,
        showMarkers: false,
      }
    case 'USER_EXITED_MARKERS_DIALOG':
      return {
        ...state,
        showMarkers: false,
      }
  }
}

/**
 * Custom React hook to manage the visibility state of markers dialog.
 *
 * This hook provides state management for whether markers are shown and if they were minimized
 * by the user. It initializes the state based on user preferences and returns both the current
 * state and a dispatch function to update it.
 *
 * @param commentsPreference - User's preference for how comments should be displayed
 *                            (expanded or collapsed by default)
 *
 * @returns A tuple containing:
 *   - markersStatus: The current state object with properties:
 *     - userMinimized: Whether the user has explicitly minimized the markers
 *     - showMarkers: Whether the markers dialog should be displayed
 *   - dispatchMarkersStatus: Dispatch function accepting the following actions:
 *     - 'SHOW_MARKERS': Display markers and ensure they're not minimized
 *     - 'USER_EXPANDED_MARKERS': User explicitly expanded markers
 *     - 'USER_MINIMIZED_MARKERS': User explicitly minimized markers
 *     - 'USER_EXITED_MARKERS_DIALOG': User exited the markers dialog
 *
 * @example
 * const [markersStatus, dispatchMarkersStatus] = useMarkersDialogStatus(
 *   CommentsPreference.Expanded || viewerData.commentsPreference || 'COLLAPSED' || 'EXPANDED'
 * );
 *
 * // Show markers
 * dispatchMarkersStatus('SHOW_MARKERS');
 *
 * // User minimizes markers
 * dispatchMarkersStatus('USER_MINIMIZED_MARKERS');
 */
export function useMarkersDialogStatus(
  commentsPreference: CommentsPreference,
): [MarkersStatusState, Dispatch<MarkersStatusAction>] {
  const [markersStatus, dispatchMarkersStatus] = useReducer(markersStatusReducer, {
    userMinimized: commentsPreference === CommentsPreference.Collapsed ? true : false,
    showMarkers: false,
  })

  useEffect(() => {
    if (commentsPreference === CommentsPreference.Visible) {
      dispatchMarkersStatus('SHOW_MARKERS')
    } else {
      dispatchMarkersStatus('USER_MINIMIZED_MARKERS')
    }
  }, [commentsPreference, dispatchMarkersStatus])

  return [markersStatus, dispatchMarkersStatus]
}
