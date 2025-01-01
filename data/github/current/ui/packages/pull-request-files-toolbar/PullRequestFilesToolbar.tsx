import {ExpandButton} from '@github-ui/expand-button'
import React from 'react'
import {ReactQueryDevtools} from '@tanstack/react-query-devtools'

import {ViewedFileProgress} from './components/ViewedFileProgress'
import {getPullRequestFilesToolbarMockData} from './test-utils/mock-data'
import type {ToolbarPayload} from './page-data/payloads/toolbar'
import {OpenCommentsSidePanelButton} from './components/OpenCommentsSidePanelButton'
import {OpenAnnotationsPanelButton} from './components/OpenAnnotationsPanelButton'
import {ReviewMenuButton} from './components/ReviewMenuButton'
import {AnalyticsProvider} from '@github-ui/analytics-provider'
import {ErrorBoundary} from '@github-ui/react-core/error-boundary'
import {CopilotDiffChatHeaderMenu} from '@github-ui/copilot-code-chat/react-no-relay/CopilotDiffChatHeaderMenu'
import {DiffViewSettings} from '@github-ui/diff-view-settings'
import {DiffViewSettingsProvider} from '@github-ui/diff-view-settings/contexts/DiffViewSettingsContext'

export interface PullRequestFilesToolbarProps {
  toolbarPayload: ToolbarPayload
}

export function PullRequestFilesToolbarPartial({toolbarPayload}: PullRequestFilesToolbarProps) {
  const fakeToolbarData = getPullRequestFilesToolbarMockData()

  const compositeToolbarData = {
    ...fakeToolbarData,
    ...toolbarPayload,
    pullRequest: {
      ...fakeToolbarData.pullRequest,
      ...toolbarPayload.pullRequest,
    },
  }

  return (
    <AnalyticsProvider
      appName="pull_request"
      category="files_tab"
      metadata={{pull_request_id: compositeToolbarData.pullRequest.id}}
    >
      <ErrorBoundary>
        <PullRequestFilesToolbar toolbarPayload={compositeToolbarData} />
        <ReactQueryDevtools initialIsOpen={false} />
      </ErrorBoundary>
    </AnalyticsProvider>
  )
}

function PullRequestFilesToolbar({toolbarPayload}: PullRequestFilesToolbarProps) {
  const [expanded, setExpanded] = React.useState(false)
  const [reviewBody, setReviewBody] = React.useState('')
  const [reviewEvent, setReviewEvent] = React.useState('COMMENT')

  const onToggleExpanded = () => {
    setExpanded(currentExpanded => !currentExpanded)
    // TODO trigger event to toggle the diff file tree
  }

  return (
    <section
      className="d-flex flex-justify-between flex-items-center pb-2 px-2"
      id="react-partial-pull-requests-files-toolbar"
    >
      <h2 className="sr-only">Pull Request Toolbar</h2>
      <ExpandButton
        alignment="left"
        ariaLabel={expanded ? 'Collapse file tree' : 'Expand file tree'}
        // TODO update this to the correct ID once the file tree is implemented
        ariaControls="pr-file-tree"
        expanded={expanded}
        onToggleExpanded={onToggleExpanded}
        testid="pr-toolbar-expand-button"
      />
      <div className="d-flex flex-items-center gap-1">
        <ViewedFileProgress totalFilesCount={toolbarPayload.totalFilesCount} toolbarPayload={toolbarPayload} />
        <OpenCommentsSidePanelButton
          pullRequestId={toolbarPayload.pullRequest.id}
          repositoryId={toolbarPayload.repositoryId}
          threadPreviews={toolbarPayload.threadPreviews}
        />
        <CopilotDiffChatHeaderMenu
          copilotAccessAllowed={toolbarPayload.copilotAccessAllowed}
          pullRequestId={toolbarPayload.pullRequest.id}
          entriesCount={toolbarPayload.totalFilesCount}
        />
        <OpenAnnotationsPanelButton annotations={toolbarPayload.annotations} />
        <ReviewMenuButton
          reviewBody={reviewBody}
          reviewEvent={reviewEvent}
          onAddReview={() => ({success: true})}
          onCancelReview={() => ({success: true})}
          onSumbitReview={() => ({success: true})}
          onUpdateReviewBody={body => setReviewBody(body)}
          onUpdateReviewEvent={event => setReviewEvent(event)}
          currentUserLogin="monalisa"
          pullRequest={toolbarPayload.pullRequest}
        />
        <DiffViewSettingsProvider viewSettings={toolbarPayload.viewSettings}>
          <DiffViewSettings lineSpacingPreferenceAvailable={false} reloadOnChange />
        </DiffViewSettingsProvider>
      </div>
    </section>
  )
}
