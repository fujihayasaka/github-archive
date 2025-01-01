import {ensurePreviousActiveDialogIsClosed} from '@github-ui/conversations/ensure-previous-active-dialog-is-closed'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {AlertIcon} from '@primer/octicons-react'
import {Button} from '@primer/react'
import {useCallback, useRef, useState} from 'react'

import {AnnotationsSidePanel} from './AnnotationsSidePanel'
import type {AnnotationsPayload} from '../page-data/payloads/annotations'

export interface OpenAnnotationsPanelButtonProps {
  annotations: AnnotationsPayload
}

/**
 *
 * Renders a button that opens the annotations side panel
 * Contains the total number of annotations plus the icon
 */
export function OpenAnnotationsPanelButton({annotations}: OpenAnnotationsPanelButtonProps) {
  const [sidePanelIsOpen, setSidePanelIsOpen] = useState(false)
  const toggleSidePanelRef = useRef<HTMLButtonElement>(null)

  const handleClose = useCallback(() => setSidePanelIsOpen(false), [])

  const totalAnnotationsCount = annotations.length

  return totalAnnotationsCount > 0 ? (
    <div className="d-flex flex-items-center">
      <ErrorBoundary
        fallback={
          <Button
            aria-label="The annotations side panel cannot currently be opened."
            icon={AlertIcon}
            size="small"
            variant="invisible"
          />
        }
      >
        <Button
          ref={toggleSidePanelRef}
          aria-label="Open annotations side panel"
          count={totalAnnotationsCount}
          leadingVisual={AlertIcon}
          size="small"
          onClick={() => {
            ensurePreviousActiveDialogIsClosed()
            setSidePanelIsOpen(true)
          }}
        />
        <AnnotationsSidePanel
          annotations={annotations}
          isOpen={sidePanelIsOpen}
          returnFocusRef={toggleSidePanelRef}
          onClose={handleClose}
        />
      </ErrorBoundary>
    </div>
  ) : null
}
