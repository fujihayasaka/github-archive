import {ListView} from '@github-ui/list-view'
import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemLeadingVisual} from '@github-ui/list-view/ListItemLeadingVisual'
import {ListItemMainContent} from '@github-ui/list-view/ListItemMainContent'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {useQuery} from '@github-ui/react-query'
import {CommentIcon, IssueOpenedIcon} from '@primer/octicons-react'
import {RelativeTime} from '@primer/react'
import {CopilotAPIClient} from '.././utils/copilot-api-client'
import styles from '../DashboardLists.module.css'
import type {DashboardIssue} from '../types'
import {IssueSummary} from './IssueSummary'

interface IssuesListProps {
  issues: DashboardIssue[]
  prompt: string
  temperature: number
}

export function IssuesList({issues, prompt, temperature}: IssuesListProps) {
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

  if (issues.length === 0) {
    return (
      <div className={styles.EmptyList}>
        <IssueOpenedIcon size={16} className={styles.HeadingIcon} />
        <div>No Issues</div>
      </div>
    )
  }

  return (
    <ListView title="Issues" ariaLabelledBy="issues_heading" className={styles.List}>
      {issues.map(issue => (
        <ListItem
          className={styles.ListItemOverride}
          key={issue.id}
          title={
            <ListItemTitle
              containerClassName={styles.titleContainerOverride}
              headingClassName={styles.titleOverride}
              value={issue.title}
              href={issue.permalink}
            />
          }
          metadata={
            <>
              {issue.commentCount > 0 && (
                <ListItemMetadata>
                  <div className={styles.commentCount}>
                    <CommentIcon size={16} /> <span>{issue.commentCount}</span>
                    <span className="sr-only">{issue.commentCount === 1 ? ' comment' : ' comments'}</span>
                  </div>
                </ListItemMetadata>
              )}
              <ListItemMetadata className={styles.titleOverride}>
                <RelativeTime className={styles.timeOverride} format="micro" datetime={issue.updatedAt} />
              </ListItemMetadata>
            </>
          }
        >
          <ListItemLeadingContent>
            <ListItemLeadingVisual className={styles.leadingVisualOverride} icon={IssueOpenedIcon} color="green" />
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
  )
}
