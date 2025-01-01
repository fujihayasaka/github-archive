import {ListItemActionBar, type ListItemActionBarProps} from '@github-ui/list-view/ListItemActionBar'
import type {CopilotCheckRunFailureContext} from '../../../page-data/payloads/status-checks'
import {publishOpenCopilotChat} from '@github-ui/copilot-chat/utils/copilot-chat-events'
import {CopilotChatIntents} from '@github-ui/copilot-chat/utils/copilot-chat-types'
import {ArrowRightIcon, CopilotIcon} from '@primer/octicons-react'
import {ActionList} from '@primer/react'
import {useCallback} from 'react'
import styles from './StatusCheckRowActionBar.module.css'
import {getFailedActionsJobPrompt} from '@github-ui/copilot-chat/utils/prompts'
import {useAnalytics} from '@github-ui/use-analytics'

export interface Props {
  copilotCheckRunFailureContext?: CopilotCheckRunFailureContext | null
  targetUrl?: string | null
}

function CopilotExplainErrorMenuItem({failureContext}: {failureContext: CopilotCheckRunFailureContext}) {
  const onSelect = useCallback(
    () =>
      publishOpenCopilotChat({
        id: 'copilot-explain-error-action',
        intent: CopilotChatIntents.actionsAgent,
        content: getFailedActionsJobPrompt(failureContext.jobId),
        references: [],
      }),
    [failureContext.jobId],
  )

  return (
    <ActionList.Item onSelect={onSelect}>
      Explain error
      <ActionList.LeadingVisual>
        <CopilotIcon />
      </ActionList.LeadingVisual>
    </ActionList.Item>
  )
}

function ViewDetailsMenuItem({targetUrl}: {targetUrl: string}) {
  const {sendAnalyticsEvent} = useAnalytics()

  const sendEvent = useCallback(() => {
    sendAnalyticsEvent('status_check_row_action_bar.view_details_click', 'VIEW_DETAILS_MENU_ITEM')
  }, [sendAnalyticsEvent])

  return (
    <ActionList.LinkItem href={targetUrl} onClick={sendEvent}>
      View details
      <ActionList.LeadingVisual>
        <ArrowRightIcon />
      </ActionList.LeadingVisual>
    </ActionList.LinkItem>
  )
}

export function StatusCheckRowActionBar({copilotCheckRunFailureContext, targetUrl}: Props) {
  const staticMenuActions: ListItemActionBarProps['staticMenuActions'] = []

  if (copilotCheckRunFailureContext != null) {
    staticMenuActions.push({
      key: 'copilot-explain-error',
      render: () => <CopilotExplainErrorMenuItem failureContext={copilotCheckRunFailureContext} />,
    })
  }

  if (targetUrl) {
    staticMenuActions.push({
      key: 'view-details',
      render: () => <ViewDetailsMenuItem targetUrl={targetUrl} />,
    })
  }

  // The label becomes "More actions" when the tooltip appears
  return (
    <ListItemActionBar label="actions" staticMenuActions={staticMenuActions} className={styles.statusCheckActionBar} />
  )
}
