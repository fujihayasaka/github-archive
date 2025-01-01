import {IssueViewer} from '@github-ui/issue-viewer/IssueViewer'
import {IssueViewerContextProvider} from '@github-ui/issue-viewer/IssueViewerContextProvider'
import {IssueViewerLoading} from '@github-ui/issue-viewer/IssueViewerLoading'
import type {OptionConfig} from '@github-ui/issue-viewer/OptionConfig'
import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import {noop} from '@github-ui/noop'
import {LinkExternalIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
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

  const openIssueInNewTabButton = useMemo(() => {
    return (
      <IconButton
        icon={LinkExternalIcon}
        variant="invisible"
        aria-label="Open issue in new tab"
        onClick={() => {
          window.open(issue.href, '_blank')
        }}
      />
    )
  }, [issue.href])

  const optionConfig: OptionConfig = useMemo(
    () => ({
      navigate: noop,
      insideSidePanel: true,
      shouldSkipSetDocumentTitle: true,
      titleAs: 'h2',
      useViewportQueries: false,
      withLiveUpdates: true,
      onIssueDelete: onClose,
      additionalHeaderActions: openIssueInNewTabButton,
      showRepositoryPill: true,
    }),
    [onClose, openIssueInNewTabButton],
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
