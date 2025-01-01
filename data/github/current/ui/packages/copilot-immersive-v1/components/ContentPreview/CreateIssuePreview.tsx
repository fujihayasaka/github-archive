import {IssueCreateInitialValuesContextProvider} from '@github-ui/issue-create/IssueCreateInitialValuesContext'
import {IssueViewerLoading} from '@github-ui/issue-viewer/IssueViewerLoading'
import type {OptionConfig} from '@github-ui/issue-viewer/OptionConfig'
import {
  InternalIssueNewPageUrlArgumentsMetadata,
  InternalIssueNewPageWithUrlParams,
} from '@github-ui/issues-react/InternalIssueNewPage'
import type {InternalIssueNewPageUrlArgumentsMetadataQuery} from '@github-ui/issues-react/InternalIssueNewPageUrlArgumentsMetadataQuery'
import {noop} from '@github-ui/noop'
import {memo, useEffect, useMemo, useState} from 'react'
import {useQueryLoader} from 'react-relay'

import {BROWSER_ANIMATION_DURATION} from '../../utils/constants'
import type {NewIssue} from './content-preview-types'
import styles from './IssuePreview.module.css'

export const CreateIssuePreview = memo(function IssuePreview({
  isPreviewOpening,
  issue,
  onClose,
}: {
  isPreviewOpening: boolean
  issue: NewIssue
  onClose: () => void
}) {
  const [showLoadingState, setShowLoadingState] = useState(isPreviewOpening)
  const [queryRef, loadQuery] = useQueryLoader<InternalIssueNewPageUrlArgumentsMetadataQuery>(
    InternalIssueNewPageUrlArgumentsMetadata,
  )

  // issue viewer causes lag if we try to render it while animating, so we show a loading until the animation is done.
  useEffect(() => {
    if (showLoadingState) {
      const timer = setTimeout(() => setShowLoadingState(false), BROWSER_ANIMATION_DURATION)
      return () => clearTimeout(timer)
    } else {
      loadQuery({owner: issue.owner, name: issue.repo})
    }
  }, [showLoadingState, loadQuery, issue.owner, issue.repo])

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

  if (showLoadingState) return <IssueViewerLoading optionConfig={optionConfig} />
  if (!queryRef) return null

  return (
    <div className={styles.container}>
      <IssueCreateInitialValuesContextProvider
        repository={issue.repo}
        owner={issue.owner}
        title={issue.name}
        body={issue.body}
      >
        <InternalIssueNewPageWithUrlParams urlParameterQueryData={queryRef} />
      </IssueCreateInitialValuesContextProvider>
    </div>
  )
})
