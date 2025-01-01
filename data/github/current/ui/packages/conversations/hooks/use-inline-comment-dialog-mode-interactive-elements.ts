import type {CommentSubjectTypes} from '@github-ui/commenting/CommentHeader'
import type {RefObject} from 'react'
import {useEffect} from 'react'

import {useInlineCommentDialogModeContext} from '../contexts/InlineCommentDialogModeContext'
import {hideInteractiveElements, showInteractiveElements} from '../util/hide-show-interactive-elements'

export function useInlineCommentDialogModeInteractiveElements({
  commentSubjectType,
  markerRef,
}: {
  commentSubjectType: CommentSubjectTypes | undefined // TODO: why is this ever undefined?
  markerRef: RefObject<HTMLElement>
}) {
  const {isInDialogMode} = useInlineCommentDialogModeContext()

  useEffect(() => {
    let timeout = null

    if (!isInDialogMode) {
      hideInteractiveElements(markerRef.current)
    } else if (commentSubjectType === 'commit') {
      // This delay works around a race condition between loading and rendering
      // the comment and attempting to manipulate the DOM.
      // This only affects the commit detail page, and should be removed when
      // the commit detail page is updated to work more like the PR files
      // changed page.
      timeout = setTimeout(() => {
        showInteractiveElements(markerRef.current)
      }, 100)
    } else {
      showInteractiveElements(markerRef.current)
    }

    return () => {
      if (timeout) {
        clearTimeout(timeout)
      }
    }
  }, [isInDialogMode, commentSubjectType, markerRef])
}
