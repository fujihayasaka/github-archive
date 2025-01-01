import {IssueViewer} from '@github-ui/issue-viewer/IssueViewer'
import {IssueViewerContextProvider} from '@github-ui/issue-viewer/IssueViewerContextProvider'
import type {OptionConfig} from '@github-ui/issue-viewer/OptionConfig'
import type {ItemIdentifier} from '@github-ui/issue-viewer/Types'
import {noop} from '@github-ui/noop'
import {useMemo} from 'react'

import type {Issue} from '../../utils/content-preview-types'
import styles from './IssuePreview.module.css'

export function IssuePreview({issue, onClose}: {issue: Issue; onClose: () => void}) {
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

  return (
    <div className={styles.container}>
      <IssueViewerContextProvider>
        <IssueViewer itemIdentifier={itemIdentifier} optionConfig={optionConfig} />
      </IssueViewerContextProvider>
    </div>
  )
}
