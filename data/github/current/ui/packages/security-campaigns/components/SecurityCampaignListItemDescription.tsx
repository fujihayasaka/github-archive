import {calculateDaysLeft} from '../utils/calculate-days-left'
import {ListItemDescription} from '@github-ui/list-view/ListItemDescription'
import pluralize from 'pluralize'
import {RelativeTime} from '@primer/react'
import type {SecurityCampaignStatus} from '../types/security-campaign-status'
import styles from './SecurityCampaignListItemDescription.module.css'
import {CampaignManagersText} from './CampaignManagersText'
import type {SecurityCampaign} from '../types/security-campaign'

export const SecurityCampaignListItemDescription = ({
  campaign,
  status,
  showManagers,
}: {
  campaign: SecurityCampaign
  status: SecurityCampaignStatus
  showManagers: boolean
}) => {
  const managers = showManagers ? (
    <>
      • <CampaignManagersText managers={campaign.managers} teamManagers={campaign.teamManagers} />{' '}
    </>
  ) : null

  switch (status) {
    case 'open': {
      const daysLeft = calculateDaysLeft(new Date(campaign.endsAt))
      return (
        <ListItemDescription>
          {daysLeft} {pluralize('day', daysLeft)} left {managers}
        </ListItemDescription>
      )
    }
    case 'overdue': {
      const daysOverdue = Math.abs(calculateDaysLeft(new Date(campaign.endsAt)))
      return (
        <ListItemDescription>
          {daysOverdue} {pluralize('day', daysOverdue)} <span className={styles.overdue}>overdue</span> {managers}
        </ListItemDescription>
      )
    }
    case 'completed': {
      return <ListItemDescription>Complete {managers}</ListItemDescription>
    }
    case 'closed': {
      return (
        <ListItemDescription>
          Closed <RelativeTime datetime={campaign.closedAt ?? undefined} />
        </ListItemDescription>
      )
    }
    case 'draft': {
      return (
        <ListItemDescription>
          Created <RelativeTime datetime={campaign.createdAt} />
        </ListItemDescription>
      )
    }
  }
}
