import type {MarkerNavigationImplementation} from '@github-ui/conversations'
import {noop} from '@github-ui/noop'
import {useMemo} from 'react'

export const OVERLAY_PORTAL_CONTAINER_NAME = 'commit-details-marker-portal'

export function useDiffInlineMarkerNav(): MarkerNavigationImplementation {
  return useMemo(
    () => ({
      filteredMarkers: [],
      activeGlobalMarkerID: '',
      decrementActiveMarker: noop,
      incrementActiveMarker: noop,
      onActivateGlobalMarkerNavigation: noop,
      overlayPortalContainerName: OVERLAY_PORTAL_CONTAINER_NAME,
    }),
    [],
  )
}
