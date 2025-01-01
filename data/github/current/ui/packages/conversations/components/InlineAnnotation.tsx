import {clsx} from 'clsx'
import {useRef} from 'react'

import {useInlineCommentDialogModeContext} from '../contexts/InlineCommentDialogModeContext'
import {useInlineCommentDialogModeInteractiveElements} from '../hooks/use-inline-comment-dialog-mode-interactive-elements'
import type {CommentingImplementation, DiffAnnotation} from '../types'
import {Annotation} from './Annotation'
import styles from './InlineAnnotation.module.css'

interface InlineAnnotationProps {
  annotation: DiffAnnotation
  isFirstMarker?: boolean
  commentingImplementation: CommentingImplementation
}

/**
 * Inline wrapper for the Annotation component
 * Used within inline markers to display annotations in the context of code
 */
export function InlineAnnotation({annotation, isFirstMarker, commentingImplementation}: InlineAnnotationProps) {
  const annotationRef = useRef<HTMLDivElement>(null)
  const {isInDialogMode} = useInlineCommentDialogModeContext()

  useInlineCommentDialogModeInteractiveElements({
    commentSubjectType: commentingImplementation.commentSubjectType,
    markerRef: annotationRef,
  })

  return (
    <div
      id={`annotation_${annotation.databaseId}`}
      ref={annotationRef}
      className={clsx(
        'border rounded-2 color-border-default color-shadow-small overflow-hidden',
        isFirstMarker ? 'mb-1' : 'mb-2',
        styles.inlineAnnotation,
      )}
      data-level={annotation.annotationLevel}
      data-testid={`annotation-${annotation.id}`}
      data-marker-id={`${annotation.id}`}
      // eslint-disable-next-line jsx-a11y/no-noninteractive-tabindex
      tabIndex={isInDialogMode ? 0 : -1}
    >
      <Annotation annotation={annotation} />
    </div>
  )
}
