import {Annotation} from '@github-ui/conversations/annotation'
import {ZeroState} from './ZeroState'
import {AlertIcon, FileSymlinkFileIcon, XIcon} from '@primer/octicons-react'
import {Dialog, Heading, IconButton, Link} from '@primer/react'
import {memo, useEffect, useCallback, useRef, useState, useMemo} from 'react'
import {announce} from '@github-ui/aria-live'
import {debounce} from '@github/mini-throttle'
import {AlertsFilter, getFilteredAlerts} from './AlertsFilter'
import type {AnnotationsPayload} from '../../page-data/payloads/annotations'
import styles from './AlertsSidePanel.module.css'
import {clsx} from 'clsx'
import {Tooltip} from '@primer/react/next'
import type {PageLimits} from '../../page-data/payloads/files'
import {Banner} from '@primer/react/experimental'

interface AlertsSidePanelProps {
  annotations: AnnotationsPayload
  returnFocusRef: React.RefObject<HTMLButtonElement>
  onClose: () => void
  isOpen: boolean
  pageLimits: PageLimits
}

function AnnotationHeader({
  databaseId,
  lineNumber,
  path,
  onNavigateToAnnotation,
}: {
  databaseId: number
  lineNumber: number
  path: string
  onNavigateToAnnotation: () => void
}) {
  return (
    <div className="d-flex flex-row flex-items-center py-1 px-2 bgColor-inset rounded-top-2 border-bottom">
      <h4 className="d-flex flex-items-center flex-1 min-width-0 ml-1 mr-2">
        <Tooltip direction="n" text={path} type="label">
          <Link
            className={clsx('overflow-hidden text-mono text-semibold f6 no-wrap', styles.annotationsHeaderFileName)}
            href={`#annotation_${databaseId}`}
            onClick={onNavigateToAnnotation}
            muted
          >
            {/* Ensures path is displayed in left-to-right-order despite container direction being right-to-left */}
            &lrm;{path}
          </Link>
        </Tooltip>
        <span className="f6 fgColor-muted text-normal ml-2 no-wrap">Line {lineNumber}</span>
      </h4>
      <IconButton
        as="a"
        aria-label="Jump to the alert in the diff"
        tooltipDirection="se"
        icon={FileSymlinkFileIcon}
        variant="invisible"
        href={`#annotation_${databaseId}`}
        onClick={onNavigateToAnnotation}
      />
    </div>
  )
}

/**
 *
 * Renders a side panel displaying previews of the pull request's annotations
 */
export const AlertsSidePanel = memo(function AlertsSidePanel({
  annotations,
  onClose,
  isOpen,
  pageLimits,
  returnFocusRef,
}: AlertsSidePanelProps) {
  const [filteredText, setFilteredText] = useState('')
  const filteredAnnotationIds = getFilteredAlerts(annotations, filteredText)
  const closeButtonRef = useRef<HTMLButtonElement>(null)
  const hasAlerts = annotations.length > 0
  const handleNavigateToAnnotation = useCallback(() => {
    onClose()
  }, [onClose])

  const annotationSummaries = annotations
    .map(annotation => {
      if (!annotation || !filteredAnnotationIds.has(annotation.id)) return null
      return (
        <div key={annotation.id} className="border rounded-2 bgColor-default overflow-hidden">
          <AnnotationHeader
            databaseId={annotation.databaseId}
            lineNumber={annotation.endLine}
            path={annotation.path}
            onNavigateToAnnotation={() => handleNavigateToAnnotation()}
          />
          <Annotation annotation={annotation} />
        </div>
      )
    })
    .filter(Boolean)

  const announceRef = useRef<HTMLDivElement>(null)
  const debouncedAnnounce = useMemo(() => debounce(announce, 300), [])
  useEffect(() => {
    if (!isOpen) return

    const announceText =
      annotationSummaries.length > 0
        ? `${annotationSummaries.length} ${annotationSummaries.length === 1 ? 'alert' : 'alerts'}`
        : `No alerts found`
    debouncedAnnounce(announceText, {element: announceRef.current as HTMLElement})
  }, [isOpen, debouncedAnnounce, annotationSummaries])

  if (!isOpen) return null
  return (
    <Dialog
      aria-label="Alerts list"
      initialFocusRef={closeButtonRef}
      onClose={onClose}
      position={{narrow: 'fullscreen', regular: 'right', wide: 'right'}}
      returnFocusRef={returnFocusRef}
      renderHeader={() => (
        <Dialog.Header className="p-3">
          <div className="d-flex flex-row flex-items-center flex-justify-between width-full">
            <Heading as="h3" className="f4 text-bold">
              Alerts
            </Heading>
            <IconButton
              ref={closeButtonRef}
              aria-label="Close alerts panel"
              icon={XIcon}
              variant="invisible"
              onClick={onClose}
            />
          </div>
          <AlertsFilter
            className="mt-2 width-full"
            filteredText={filteredText}
            onFilteredTextChange={setFilteredText}
          />
        </Dialog.Header>
      )}
    >
      {pageLimits.annotationsLimitExceeded && (
        <Banner
          aria-label="Warning"
          title="Warning"
          variant="warning"
          hideTitle
          description={`Only the first ${pageLimits.annotationsLimit} alerts are currently being shown.`}
          className="mb-3"
        />
      )}
      {annotationSummaries.length > 0 ? (
        <div className="d-flex flex-column position-relative width-full gap-3">{annotationSummaries}</div>
      ) : (
        <div className="d-flex flex-column position-relative width-full height-full flex-justify-center">
          <ZeroState
            heading={hasAlerts ? 'No alerts match the current filter' : 'No alerts on changes yet'}
            icon={AlertIcon}
          />
        </div>
      )}
      <div className="sr-only" aria-live="polite" aria-atomic="true" ref={announceRef} />
    </Dialog>
  )
})
