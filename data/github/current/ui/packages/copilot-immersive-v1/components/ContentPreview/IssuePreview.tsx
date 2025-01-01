import {IssueViewer} from '@github-ui/issue-viewer/IssueViewer'
import {IssueViewerContextProvider} from '@github-ui/issue-viewer/IssueViewerContextProvider'
import {IssueViewerLoading} from '@github-ui/issue-viewer/IssueViewerLoading'
import type {OptionConfig} from '@github-ui/issue-viewer/OptionConfig'
import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import {noop} from '@github-ui/noop'
import {memo, useEffect, useMemo, useState} from 'react'

import {BROWSER_ANIMATION_DURATION} from '../../utils/constants'
import type {Issue} from './content-preview-types'
import styles from './IssuePreview.module.css'

export const IssuePreview = memo(function IssuePreview({
  isPreviewOpening,
  issue,
  onClose,
}: {
  isPreviewOpening: boolean
  issue: Issue
  onClose: () => void
}) {
  const [showLoadingState, setShowLoadingState] = useState(isPreviewOpening)

  // issue viewer causes lag if we try to render it while animating, so we show a loading until the animation is done.
  useEffect(() => {
    if (showLoadingState) {
      const timer = setTimeout(() => setShowLoadingState(false), BROWSER_ANIMATION_DURATION)
      return () => clearTimeout(timer)
    }
  }, [showLoadingState])

  const optionConfig: OptionConfig = useMemo(
    () => ({
      navigate: noop,
      shouldSkipSetDocumentTitle: true,
      titleAs: 'h2',
      useViewportQueries: false,
      withLiveUpdates: true,
      onIssueDelete: onClose,
    }),
    [onClose],
  )
  const itemIdentifier: ItemIdentifier = useMemo(
    () => ({
      owner: issue.owner,
      repo: issue.repo,
      number: issue.number,
      type: 'Issue',
    }),
    [issue.number, issue.owner, issue.repo],
  )

  if (showLoadingState) return <IssueViewerLoading optionConfig={optionConfig} />

  return (
    <div className={styles.container}>
      <IssueViewerContextProvider>
        <IssueViewer itemIdentifier={itemIdentifier} optionConfig={optionConfig} />
      </IssueViewerContextProvider>
    </div>
  )
})
