import {Annotation} from '@github-ui/conversations/annotation'
import {ZeroState} from './ZeroState'
import {AlertIcon, FileSymlinkFileIcon, XIcon} from '@primer/octicons-react'
import {Dialog, Heading, IconButton, Text} from '@primer/react'
import {Tooltip} from '@primer/react/next'
import {memo, useCallback, useRef, useState} from 'react'

import {AnnotationsFilter, getFilteredAnnotations} from './AnnotationsFilter'
import type {AnnotationsPayload} from '../page-data/payloads/annotations'

interface AnnotationsSidePanelProps {
  annotations: AnnotationsPayload
  returnFocusRef: React.RefObject<HTMLButtonElement>
  onClose: () => void
  isOpen: boolean
}

function AnnotationHeader({
  lineNumber,
  path,
  onNavigateToAnnotation,
}: {
  lineNumber: number
  path: string
  onNavigateToAnnotation: () => void
}) {
  return (
    <div className="d-flex flex-row flex-items-center py-1 px-2 bgColor-inset rounded-top-2 border-bottom">
      <h4 className="d-flex flex-items-center flex-1 min-width-0 ml-1 mr-2">
        <Text
          className="overflow-hidden text-mono text-semibold f6 no-wrap"
          sx={{
            textOverflow: 'ellipsis',
            direction: 'rtl',
          }}
        >
          {path}
        </Text>
        <span className="f6 fgColor-muted text-normal ml-2 no-wrap">Line {lineNumber}</span>
      </h4>
      <Tooltip direction="se" id="jump-to-annotation" text="Jump to the annotation in the diff" type="label">
        {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
        <IconButton
          aria-labelledby="jump-to-annotation"
          icon={FileSymlinkFileIcon}
          unsafeDisableTooltip
          variant="invisible"
          onClick={onNavigateToAnnotation}
        />
      </Tooltip>
    </div>
  )
}

/**
 *
 * Renders a side panel displaying previews of the pull request's annotations
 */
export const AnnotationsSidePanel = memo(function AnnotationsSidePanel({
  annotations,
  onClose,
  isOpen,
  returnFocusRef,
}: AnnotationsSidePanelProps) {
  const [filteredText, setFilteredText] = useState('')
  const filteredAnnotationIds = getFilteredAnnotations(annotations, filteredText)
  const closeButtonRef = useRef<HTMLButtonElement>(null)
  const hasAnnotations = annotations.length > 0
  const handleNavigateToAnnotation = useCallback(() => {
    // TODO: naviagte to the annotation in the Rails diff
    onClose()
  }, [onClose])

  if (!isOpen) return null

  const annotationSummaries = annotations
    .map(annotation => {
      if (!annotation || !filteredAnnotationIds.has(annotation.id)) return null
      return (
        <div key={annotation.id} className="border rounded-2 bgColor-default overflow-hidden">
          <AnnotationHeader
            lineNumber={annotation.endLine}
            path={annotation.path}
            onNavigateToAnnotation={() => handleNavigateToAnnotation()}
          />
          <Annotation annotation={annotation} />
        </div>
      )
    })
    .filter(Boolean)

  return (
    <Dialog
      aria-label="Annotations list"
      initialFocusRef={closeButtonRef}
      onClose={onClose}
      position={{narrow: 'fullscreen', regular: 'right', wide: 'right'}}
      returnFocusRef={returnFocusRef}
      renderHeader={() => (
        <Dialog.Header className="p-3">
          <div className="d-flex flex-row flex-items-center flex-justify-between width-full">
            <Heading as="h3" className="f4 text-bold">
              Annotations
            </Heading>
            {/* eslint-disable-next-line primer-react/a11y-remove-disable-tooltip */}
            <IconButton
              ref={closeButtonRef}
              aria-label="Close annotations panel"
              icon={XIcon}
              unsafeDisableTooltip
              variant="invisible"
              onClick={onClose}
            />
          </div>
          <AnnotationsFilter
            className="mt-2 width-full"
            filteredText={filteredText}
            onFilteredTextChange={setFilteredText}
          />
        </Dialog.Header>
      )}
    >
      {annotationSummaries.length > 0 ? (
        <div className="d-flex flex-column position-relative width-full gap-3">{annotationSummaries}</div>
      ) : (
        <div className="d-flex flex-column position-relative width-full height-full flex-justify-center">
          <ZeroState
            description="Annotations will show up here as soon as there are some."
            heading={hasAnnotations ? 'No annotations match the current filter' : 'No annotations on changes yet'}
            icon={AlertIcon}
          />
        </div>
      )}
    </Dialog>
  )
})
