import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {useQuery} from '@github-ui/react-query'
import {isStaff} from '@github-ui/stats'
import {GitPullRequestIcon, IssueOpenedIcon, CommentIcon} from '@primer/octicons-react'
import {Heading, RelativeTime, Stack} from '@primer/react'
import {useMemo, useRef, useState} from 'react'
import styles from './DashboardLists.module.css'
import {IssueActionMenu} from './components/IssueActionMenu'
import {IssueSummary} from './components/IssueSummary'
import {PromptDialog} from './components/PromptDialog'
import type {DashboardIssue, DashboardPullRequest} from './types'
import {CopilotAPIClient} from './utils/copilot-api-client'
import {dashboardLocalStorage} from './utils/dashboard-local-storage'
import {getDefaultIssueSummaryPrompt} from './utils/issue-summary-prompt'

export interface DashboardListsProps {
  pullRequests: DashboardPullRequest[]
  issues: DashboardIssue[]
  userDisplayLogin: string
}

export function DashboardLists({pullRequests, issues, userDisplayLogin}: DashboardListsProps) {
  const defaultIssueSummaryPrompt = getDefaultIssueSummaryPrompt(userDisplayLogin)
  const temperature = dashboardLocalStorage.getIssueSummaryTemperature() || 0.5
  const prompt = dashboardLocalStorage.getIssueSummaryPrompt() || defaultIssueSummaryPrompt

  const client = new CopilotAPIClient()
  const {
    isPending,
    isError,
    data: issueSummariesByTitle,
    error,
  } = useQuery({
    queryKey: [issues, prompt, temperature],
    queryFn: () => client.getIssueSummariesByTitle(issues, prompt, temperature),
  })

  const userIsStaff = useMemo(() => {
    return isStaff()
  }, [])

  const promptDialogRef = useRef<HTMLDivElement>(null)
  const [showPromptDialog, setShowPromptDialog] = useState(false)
  const onDismissPromptDialog = () => {
    setShowPromptDialog(false)
  }
  const onShowPromptDialog = () => {
    setShowPromptDialog(true)
  }

  return (
    <>
      <Heading as="h2" id="pr_heading" className={styles.Heading}>
        <GitPullRequestIcon size={16} className={styles.HeadingIcon} />
        Pull Requests
      </Heading>
      {pullRequests.length > 0 ? (
        <ListView title="Pull Requests" aria-labelledby="pr_heading" className={styles.List}>
          {pullRequests.map(pullRequest => (
            <ListItem
              key={pullRequest.id}
              title={<ListItemTitle value={pullRequest.title} href={pullRequest.permalink} />}
              className={styles.ListItem}
              metadata={
                <>
                  {pullRequest.commentCount > 0 && (
                    <ListItemMetadata>
                      <div>
                        <CommentIcon size={16} /> <span>{pullRequest.commentCount}</span>
                        <span className="sr-only">{pullRequest.commentCount === 1 ? ' comment' : ' comments'}</span>
                      </div>
                    </ListItemMetadata>
                  )}
                  <ListItemMetadata>
                    <RelativeTime datetime={pullRequest.updatedAt} />
                  </ListItemMetadata>
                </>
              }
            >
              <ListItemLeadingContent>
                <ListItemLeadingVisual icon={GitPullRequestIcon} color="green" />
              </ListItemLeadingContent>
            </ListItem>
          ))}
        </ListView>
      ) : (
        <div className={styles.EmptyList}>
          <GitPullRequestIcon size={16} className={styles.HeadingIcon} />
          <div>No Pull Requests</div>
        </div>
      )}

      {showPromptDialog && userIsStaff && (
        <PromptDialog
          promptDialogRef={promptDialogRef}
          initialPrompt={prompt}
          initialTemperature={temperature}
          onDismiss={onDismissPromptDialog}
        />
      )}

      <Stack direction="horizontal" justify="space-between">
        <Heading as="h2" id="issues_heading" className={styles.Heading}>
          <IssueOpenedIcon size={16} className={styles.HeadingIcon} />
          Issues
        </Heading>
        <IssueActionMenu onShowPromptDialog={onShowPromptDialog} />
      </Stack>

      {issues.length > 0 ? (
        <ListView title="Issues" aria-labelledby="issues_heading" className={styles.List}>
          {issues.map(issue => (
            <ListItem
              key={issue.id}
              title={<ListItemTitle value={issue.title} href={issue.permalink} />}
              metadata={
                <>
                  {issue.commentCount > 0 && (
                    <ListItemMetadata>
                      <div>
                        <CommentIcon size={16} /> <span>{issue.commentCount}</span>
                        <span className="sr-only">{issue.commentCount === 1 ? ' comment' : ' comments'}</span>
                      </div>
                    </ListItemMetadata>
                  )}
                  <ListItemMetadata>
                    <RelativeTime datetime={issue.updatedAt} />
                  </ListItemMetadata>
                </>
              }
            >
              <ListItemLeadingContent>
                <ListItemLeadingVisual icon={IssueOpenedIcon} color="green" />
              </ListItemLeadingContent>
              <ListItemMainContent>
                <IssueSummary
                  isPending={isPending}
                  isError={isError}
                  summary={issueSummariesByTitle?.get(issue.title)}
                  error={error}
                />
              </ListItemMainContent>
            </ListItem>
          ))}
        </ListView>
      ) : (
        <div className={styles.EmptyList}>
          <IssueOpenedIcon size={16} className={styles.HeadingIcon} />
          <div>No Issues</div>
        </div>
      )}
    </>
  )
}
