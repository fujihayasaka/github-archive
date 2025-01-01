import {RowsLoading} from './RowsLoading'
import {AlertsListError} from './AlertsListError'
import {Blankslate} from '@primer/react/experimental'
import {ShieldCheckIcon} from '@primer/octicons-react'
import type {SecurityCampaignAlertGroup} from '../types/security-campaign-alert-group'
import React from 'react'
import {BlankslateListItem} from './BlankslateListItem'

export type AlertsListGroupsProps = {
  groups: SecurityCampaignAlertGroup[]
  query: string
  isLoading: boolean
  isError: boolean
  renderGroup: (group: SecurityCampaignAlertGroup) => React.ReactNode
}

export function AlertsListGroups({groups, query, isLoading, isError, renderGroup}: AlertsListGroupsProps) {
  if (isLoading) {
    return <RowsLoading rowCount={5} />
  }

  if (isError) {
    return <AlertsListError />
  }

  if (groups.length === 0) {
    if (query.trim() === 'is:open') {
      return (
        <BlankslateListItem spacious>
          <Blankslate.Heading>All alerts have been closed</Blankslate.Heading>
        </BlankslateListItem>
      )
    } else {
      return (
        <BlankslateListItem spacious>
          <Blankslate.Visual>
            <ShieldCheckIcon size="medium" />
          </Blankslate.Visual>
          <Blankslate.Heading>No alerts found</Blankslate.Heading>
        </BlankslateListItem>
      )
    }
  }

  return groups.map(group => <React.Fragment key={group.title}>{renderGroup(group)}</React.Fragment>)
}
