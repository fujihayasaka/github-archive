import {isFeatureEnabled} from '@github-ui/feature-flags'
import {isStaff} from '@github-ui/stats'
import {IssueOpenedIcon} from '@primer/octicons-react'
import {Heading} from '@primer/react'
import {useMemo, useRef, useState} from 'react'
import styles from './DashboardLists.module.css'
import {IssueActionMenu} from './components/IssueActionMenu'
import {IssuesList} from './components/IssuesList'
import {PromptDialog} from './components/PromptDialog'
import {PullRequestsList} from './components/PullRequestsList'
import type {DashboardIssue} from './types'
import {dashboardLocalStorage} from './utils/dashboard-local-storage'
import {getDefaultIssueSummaryPrompt} from './utils/issue-summary-prompt'

export interface DashboardListsProps {
  issues: DashboardIssue[]
  userDisplayLogin: string
}

const DEFAULT_TEMPERATURE = 0.5

export function DashboardLists({issues, userDisplayLogin}: DashboardListsProps) {
  const defaultIssueSummaryPrompt = getDefaultIssueSummaryPrompt(userDisplayLogin)
  const temperature = dashboardLocalStorage.getIssueSummaryTemperature() || DEFAULT_TEMPERATURE
  const prompt = dashboardLocalStorage.getIssueSummaryPrompt() || defaultIssueSummaryPrompt

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
      <PullRequestsList userDisplayLogin={userDisplayLogin} />

      {isFeatureEnabled('dashboard_lists') && (
        <>
          {showPromptDialog && userIsStaff && (
            <PromptDialog
              promptDialogRef={promptDialogRef}
              initialPrompt={prompt}
              initialTemperature={temperature}
              onDismiss={onDismissPromptDialog}
            />
          )}

          <div className={styles.HeadingContainer}>
            <Heading as="h2" id="issues_heading" className={styles.Heading}>
              <IssueOpenedIcon size={16} className={styles.HeadingIcon} />
              Issues
            </Heading>
            <IssueActionMenu onShowPromptDialog={onShowPromptDialog} />
          </div>
          <IssuesList issues={issues} prompt={prompt} temperature={temperature} />
        </>
      )}
    </>
  )
}
