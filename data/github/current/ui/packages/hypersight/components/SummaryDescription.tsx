import {SegmentedControl, Link} from '@primer/react'
import {SkeletonText} from '@primer/react/experimental'
import Markdown from 'react-markdown'
import {useEffect, useState} from 'react'
import {summarizeDescription} from '../utils/summarize-description'
import type {HydratedIssueReference, PullRequest, PullRequestSummaryState, Template} from '../utils/types'
import styles from './PullRequestSummary.module.css'

interface SummaryDescriptionProps {
  apiUrl: string
  pullRequest: PullRequest
  extractedIssues: HydratedIssueReference[]
  template: Template
}

const VIEW_MODES = {
  SUMMARY: 'summary',
  FULL: 'full',
} as const

type ViewMode = (typeof VIEW_MODES)[keyof typeof VIEW_MODES]

export function SummaryDescription({apiUrl, pullRequest, extractedIssues, template}: SummaryDescriptionProps) {
  const [summaryState, setSummaryState] = useState<PullRequestSummaryState>({status: 'pending'})
  const [viewMode, setViewMode] = useState<ViewMode>(VIEW_MODES.SUMMARY)

  useEffect(() => {
    let isSubscribed = true

    const fetchSummary = async () => {
      try {
        setSummaryState({status: 'fetching'})
        const summary = await summarizeDescription(apiUrl, template, pullRequest, extractedIssues)

        if (isSubscribed) {
          setSummaryState({status: 'complete', summary})
        }
      } catch (err: unknown) {
        if (!isSubscribed) return
        const errMsg = err instanceof Error ? err.message : 'An error occurred while generating the summary'
        setSummaryState({status: 'error', error: errMsg})
      }
    }

    fetchSummary()
    return () => {
      isSubscribed = false
    }
  }, [apiUrl, pullRequest, extractedIssues, template])

  return (
    <div className={styles.summaryBox}>
      <div className={styles.summaryTypeSelector}>
        <SegmentedControl
          aria-label="Pull Request Description Views"
          onChange={index => setViewMode(index === 0 ? VIEW_MODES.SUMMARY : VIEW_MODES.FULL)}
        >
          <SegmentedControl.Button selected={viewMode === VIEW_MODES.SUMMARY}>Summary</SegmentedControl.Button>
          <SegmentedControl.Button selected={viewMode === VIEW_MODES.FULL}>Full Description</SegmentedControl.Button>
        </SegmentedControl>
      </div>

      {viewMode === VIEW_MODES.SUMMARY ? (
        <SummaryView summaryState={summaryState} pullRequest={pullRequest} />
      ) : (
        <FullDescriptionView pullRequest={pullRequest} />
      )}
    </div>
  )
}

function SummaryView({summaryState, pullRequest}: {summaryState: PullRequestSummaryState; pullRequest: PullRequest}) {
  if (summaryState.status === 'pending' || summaryState.status === 'fetching') {
    return <SkeletonText lines={3} style={{width: '100%'}} aria-label="Loading summary" />
  }

  if (summaryState.status === 'error') {
    return <p className={styles.errorText}>{summaryState.error}</p>
  }

  if (summaryState.status === 'complete' && summaryState.summary) {
    return (
      <>
        <Markdown>{summaryState.summary}</Markdown>
        <div className={styles.summaryFooter}>
          Summarised from{' '}
          <Link
            inline
            href={`/${pullRequest.base.repo.owner.login}/${pullRequest.base.repo.name}/pull/${pullRequest.number}`}
          >
            {pullRequest.base.repo.owner.login}/{pullRequest.base.repo.name}#{pullRequest.number}
          </Link>
        </div>
      </>
    )
  }

  return null
}

function FullDescriptionView({pullRequest}: {pullRequest: PullRequest}) {
  return (
    <div className={styles.fullDescription}>
      {pullRequest.body ? (
        <Markdown>{pullRequest.body}</Markdown>
      ) : (
        <p className="color-fg-muted">No description provided.</p>
      )}
    </div>
  )
}
