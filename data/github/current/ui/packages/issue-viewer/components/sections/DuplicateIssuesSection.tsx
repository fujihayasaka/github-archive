import {ReadonlySectionHeader} from '@github-ui/issue-metadata/ReadonlySectionHeader'
import {Section} from '@github-ui/issue-metadata/Section'
import {IconButton, Label, Link} from '@primer/react'
import {graphql, useFragment} from 'react-relay'
import type {DuplicateIssuesSectionFragment$key} from './__generated__/DuplicateIssuesSectionFragment.graphql'
import {useMemo, useState} from 'react'
import {Octicon} from '@primer/react/deprecated'
import type {IssueState, IssueStateReason} from '@github-ui/item-picker/IssuePickerIssue.graphql'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'
import {IssueOpenedIcon, IssueClosedIcon, SkipIcon, ThumbsupIcon, ThumbsdownIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import {sendEvent} from '@github-ui/hydro-analytics'
import type {KeyTypeData} from 'react-relay/relay-hooks/helpers'
import styles from './DuplicateIssuesSection.module.css'

const DuplicateIssuesSectionFragment = graphql`
  fragment DuplicateIssuesSectionFragment on Issue {
    id
    number
    url
    repository {
      nameWithOwner
    }
    duplicateIssues(first: 3) {
      nodes {
        id
        number
        title
        state
        stateReason
        url
        repository {
          nameWithOwner
        }
      }
    }
  }
`

type DuplicateIssuesSectionProps = {
  issue: DuplicateIssuesSectionFragment$key
}

export function DuplicateIssuesSection({issue}: DuplicateIssuesSectionProps) {
  const semanticIssuesEnabled = useFeatureFlag('elasticsearch_semantic_indexing_issues_show_dupes')
  if (!semanticIssuesEnabled) {
    return null
  }

  return <DuplicateIssuesSectionInternal issue={issue} />
}

function DuplicateIssuesSectionInternal({issue}: DuplicateIssuesSectionProps) {
  const data = useFragment(DuplicateIssuesSectionFragment, issue)
  const duplicateIssues = useMemo(() => {
    return data.duplicateIssues?.nodes?.filter(node => !!node) || []
  }, [data.duplicateIssues])

  return (
    <Section
      id="duplicate-issues-section"
      sectionHeader={
        <div className="d-flex flex-row flex-items-center">
          <ReadonlySectionHeader title="Related issues" />
          <Label variant="accent">Staff</Label>
        </div>
      }
      emptyText={duplicateIssues.length ? undefined : 'No related issues found'}
    >
      {duplicateIssues.map(duplicate => (
        <DuplicateIssueItem key={duplicate.id} issue={data} duplicateIssue={duplicate} />
      ))}
    </Section>
  )
}

type FeedbackType = 'related' | 'not-related'

type DuplicateIssue = {
  id: string
  number: number
  repository: {
    nameWithOwner: string
  }
  state: IssueState
  stateReason: IssueStateReason | null | undefined
  title: string
  url: string
}

function DuplicateIssueItem({
  issue,
  duplicateIssue,
}: {
  key: string
  issue: KeyTypeData<DuplicateIssuesSectionFragment$key>
  duplicateIssue: DuplicateIssue
}) {
  const [submittedFeedback, setSubmittedFeedback] = useState<FeedbackType | undefined>(undefined)
  const feedbackSubmitted = useMemo(() => !!submittedFeedback, [submittedFeedback])
  const duplicateIssueXref = useMemo(
    () => `${duplicateIssue.repository.nameWithOwner}#${duplicateIssue.number}`,
    [duplicateIssue],
  )

  return (
    <div className="px-2 py-1 d-flex flex-row" role="listitem">
      <IssueIcon state={duplicateIssue.state} stateReason={duplicateIssue.stateReason} />
      <div className="width-full d-flex flex-row">
        <div className={clsx('d-flex flex-column flex-1 mr-2', styles.duplicateIssuesDisplay)}>
          <Link className="fgColor-default f5 text-bold mb-1" href={duplicateIssue.url} target="_blank">
            {duplicateIssue.title}
          </Link>
          <span className="fgColor-muted f6">{duplicateIssueXref}</span>
        </div>
        <IconButton
          className={clsx('mr-1', submittedFeedback === 'related' ? 'fgColor-default bgColor-muted' : 'fgColor-muted')}
          size="small"
          icon={ThumbsupIcon}
          variant="invisible"
          aria-label="Related."
          disabled={feedbackSubmitted}
          onClick={() => {
            const feedback = 'related'
            submitFeedback(feedback, issue, duplicateIssue)
            setSubmittedFeedback(feedback)
          }}
        />
        <IconButton
          className={submittedFeedback === 'not-related' ? 'fgColor-default bgColor-muted' : 'fgColor-muted'}
          size="small"
          icon={ThumbsdownIcon}
          variant="invisible"
          aria-label="Not related."
          disabled={feedbackSubmitted}
          onClick={() => {
            const feedback = 'not-related'
            submitFeedback(feedback, issue, duplicateIssue)
            setSubmittedFeedback(feedback)
          }}
        />
      </div>
    </div>
  )
}

function IssueIcon({state, stateReason}: {state: IssueState; stateReason: IssueStateReason | null | undefined}) {
  let icon = IssueOpenedIcon
  let fill = 'open.fg'

  if (state === 'CLOSED') {
    icon = stateReason === 'COMPLETED' ? IssueClosedIcon : SkipIcon
    fill = stateReason === 'COMPLETED' ? 'done.fg' : 'muted.fg'
  }

  return <Octicon className="mr-2" icon={icon} sx={{path: {fill}, height: 20}} />
}

function submitFeedback(
  feedback: FeedbackType,
  issue: KeyTypeData<DuplicateIssuesSectionFragment$key>,
  duplicateIssue: DuplicateIssue,
): void {
  sendEvent('copilot.related_issues.user_feedback', {
    issueNumber: issue.number,
    issueUrl: issue.url,
    issueRepository: issue.repository.nameWithOwner,
    duplicateIssueId: duplicateIssue.id,
    duplicateIssueNumber: duplicateIssue.number,
    duplicateIssueRepository: duplicateIssue.repository.nameWithOwner,
    duplicateIssueUrl: duplicateIssue.url,
    feedback,
  })
}
