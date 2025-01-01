import {SplitPageLayout} from '@primer/react'
import styles from './HypersightLayout.module.css'
import {PullRequestSummary} from '../components/PullRequestSummary'
import {FakePullRequestNav} from '../components/FakePullRequestNav'
import TableOfContents from '../components/TableOfContents'
import MarkdownWalkthrough from '../components/MarkdownWalkthrough'
import {OtherChanges} from '../components/OtherChanges'
import {PullRequestQuestions} from '../components/PullRequestQuestions'
import WalkthroughConfiguration from '../components/WalkthroughConfiguration'
import {HunkProvider} from '../utils/HunkContext'
import type {
  PullRequest,
  NavigationUrls,
  FileCategory,
  DiffData,
  ExplanationDepth,
  HydratedIssueReference,
  DiffHunk,
} from '../utils/types'

interface HypersightLayoutProps {
  pullRequest: PullRequest
  urls: NavigationUrls
  markdownContent: string
  isWalkthroughComplete: boolean
  walkthroughDiffHunks: DiffHunk[]
  nonProcessedDiffs: Record<FileCategory, DiffData[]>
  apiUrl: string
  extractedIssues: HydratedIssueReference[]
  depth: ExplanationDepth
  onDepthChange: (newDepth: ExplanationDepth) => void
  preferences: string
  onPreferencesChange: (newPreferences: string) => void
}

export default function HypersightLayout({
  pullRequest,
  urls,
  markdownContent,
  isWalkthroughComplete,
  walkthroughDiffHunks,
  nonProcessedDiffs,
  apiUrl,
  extractedIssues,
  depth,
  onDepthChange,
  preferences,
  onPreferencesChange,
}: HypersightLayoutProps) {
  return (
    <div className={styles.container}>
      <SplitPageLayout>
        <SplitPageLayout.Header divider="none" padding="none">
          <PullRequestSummary pullRequest={pullRequest} />
          <FakePullRequestNav urls={urls} />
        </SplitPageLayout.Header>
        <SplitPageLayout.Pane position="start" padding="none" width="large">
          <TableOfContents />
        </SplitPageLayout.Pane>
        <SplitPageLayout.Content as="div" padding="none">
          <div className={styles.contentPane}>
            <WalkthroughConfiguration
              depth={depth}
              onDepthChange={onDepthChange}
              preferences={preferences}
              onPreferencesChange={onPreferencesChange}
            />
            <HunkProvider hunks={walkthroughDiffHunks}>
              <MarkdownWalkthrough markdownContent={markdownContent} />
              {isWalkthroughComplete && (
                <>
                  <OtherChanges nonProcessedDiffs={nonProcessedDiffs} />
                  <PullRequestQuestions
                    apiUrl={apiUrl}
                    pullRequest={pullRequest}
                    extractedIssues={extractedIssues}
                    diffs={walkthroughDiffHunks}
                  />
                </>
              )}
            </HunkProvider>
          </div>
        </SplitPageLayout.Content>
      </SplitPageLayout>
    </div>
  )
}
