import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import type {ListItemTrailingBadge} from '@github-ui/list-view/ListItemTrailingBadge'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import React from 'react'
import type {SecurityCampaignAlertGroup} from '../types/security-campaign-alert-group'

import styles from './AlertListGroup.module.css'
import type {AlertParentLink} from '../types/security-campaign-alert'
import {alertParentLinkHref} from '../utils/alert-parent-link'
import {IssueLink} from './IssueLink'

export interface AlertListGroupProps {
  group: SecurityCampaignAlertGroup
  expanded: boolean
  onExpandedChange?: (group: string) => void
  renderMetadata?: (group: SecurityCampaignAlertGroup) => React.ReactNode
  renderTrailingBadges?: (group: SecurityCampaignAlertGroup) => Array<React.ReactElement<typeof ListItemTrailingBadge>>
  renderGroup: (group: SecurityCampaignAlertGroup) => React.ReactNode
  alertParentLink: AlertParentLink
}

export function AlertListGroup({
  group,
  expanded,
  onExpandedChange,
  renderMetadata,
  renderTrailingBadges,
  renderGroup,
  alertParentLink,
}: AlertListGroupProps): JSX.Element {
  const onToggle = React.useCallback(() => {
    onExpandedChange?.(group.title)
  }, [onExpandedChange, group.title])

  const toggleOnKeyDown = (event: React.KeyboardEvent) => {
    // eslint-disable-next-line @github-ui/ui-commands/no-manual-shortcut-logic
    if ((event.key === 'ArrowLeft' && expanded) || (event.key === 'ArrowRight' && !expanded)) {
      onToggle()
    }
  }

  return (
    <>
      <ListItem
        title={
          <ListItemTitle
            value={group.title}
            href={
              group.group?.kind === 'repository'
                ? alertParentLinkHref(alertParentLink, {
                    owner: group.group.repository.ownerLogin,
                    repo: group.group.repository.name,
                  })
                : undefined
            }
            trailingBadges={renderTrailingBadges?.(group)}
          >
            {group.issue && <IssueLink issue={group.issue} />}
          </ListItemTitle>
        }
        onKeyDown={toggleOnKeyDown}
        metadata={renderMetadata?.(group)}
        className={styles.ListItem_0}
      >
        <ListItemLeadingContent className={styles.ListItemLeadingContent_0}>
          <IconButton
            aria-label={`Toggle ${group.title}`}
            icon={expanded ? ChevronDownIcon : ChevronRightIcon}
            variant="invisible"
            size="large"
            onClick={onToggle}
            onKeyDown={toggleOnKeyDown}
          />
        </ListItemLeadingContent>
      </ListItem>
      {expanded && renderGroup(group)}
    </>
  )
}
