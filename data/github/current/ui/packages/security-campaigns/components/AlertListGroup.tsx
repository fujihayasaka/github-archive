import {ListItem} from '@github-ui/list-view/ListItem'
import {ListItemLeadingContent} from '@github-ui/list-view/ListItemLeadingContent'
import {ListItemMetadata} from '@github-ui/list-view/ListItemMetadata'
import {ListItemTitle} from '@github-ui/list-view/ListItemTitle'
import {ChevronDownIcon, ChevronRightIcon} from '@primer/octicons-react'
import {IconButton} from '@primer/react'
import React from 'react'
import type {SecurityCampaignAlertGroup} from '../types/security-campaign-alert-group'
import {CampaignProgressBar} from './CampaignProgressBar'

export interface AlertListGroupProps {
  group: SecurityCampaignAlertGroup
  expanded: boolean
  onExpandedChange?: (group: string) => void
  renderGroup: (group: SecurityCampaignAlertGroup) => React.ReactNode
}

export function AlertListGroup({group, expanded, onExpandedChange, renderGroup}: AlertListGroupProps): JSX.Element {
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
        sx={{backgroundColor: 'canvas.subtle', paddingY: 2}}
        title={<ListItemTitle value={group.title} href={group.titleHref} />}
        onKeyDown={toggleOnKeyDown}
        metadata={
          <ListItemMetadata>
            <CampaignProgressBar
              openCount={group.openCount}
              closedCount={group.closedCount}
              openWithLinksCount={group.openWithLinksCount}
            />
          </ListItemMetadata>
        }
      >
        <ListItemLeadingContent sx={{paddingLeft: 0}}>
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
