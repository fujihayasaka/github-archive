import {ensurePreviousActiveDialogIsClosed} from '@github-ui/conversations/ensure-previous-active-dialog-is-closed'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {AlertIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {useCallback, useRef, useState} from 'react'

import {AlertsSidePanel} from './AlertsSidePanel'
import {useMarkersData} from '../../page-data/loaders/use-markers-data'
import type {PageLimits} from '../../page-data/payloads/files'

export interface OpenAlertsPanelButtonProps {
  basePath: string
  pageLimits: PageLimits
}

/**
 *
 * Renders a button that opens the annotations side panel
 * Contains the total number of annotations plus the icon
 */
export function OpenAlertsPanelButton({basePath, pageLimits}: OpenAlertsPanelButtonProps) {
  const [sidePanelIsOpen, setSidePanelIsOpen] = useState(false)
  const toggleSidePanelRef = useRef<HTMLButtonElement>(null)

  const handleClose = useCallback(() => setSidePanelIsOpen(false), [])

  const markers = useMarkersData({basePath}).data

  if (!markers || !markers.annotations) {
    return null
  }

  const annotations = Object.values(markers.annotations)

  const totalAnnotationsCount = annotations.length

  return totalAnnotationsCount > 0 ? (
    <div className="d-flex flex-items-center">
      <ErrorBoundary
        fallback={
          <Button
            aria-label="The alerts side panel cannot currently be opened."
            icon={AlertIcon}
            size="small"
            variant="invisible"
          />
        }
      >
        <Button
          ref={toggleSidePanelRef}
          aria-label="Open alerts side panel"
          count={totalAnnotationsCount}
          leadingVisual={AlertIcon}
          size="small"
          onClick={() => {
            ensurePreviousActiveDialogIsClosed()
            setSidePanelIsOpen(true)
          }}
        >
          <span className="d-none d-xl-block">Alerts</span>
        </Button>
        <AlertsSidePanel
          annotations={annotations}
          isOpen={sidePanelIsOpen}
          pageLimits={pageLimits}
          returnFocusRef={toggleSidePanelRef}
          onClose={handleClose}
        />
      </ErrorBoundary>
    </div>
  ) : null
}
