import {ProgressBar, Stack} from '@primer/react'
import pluralize from 'pluralize'

import styles from './CampaignProgressBar.module.css'

export interface CampaignProgressBarProps {
  openCount: number | undefined
  closedCount: number | undefined
  openWithLinksCount: number | undefined
}

const percentFormatter = new Intl.NumberFormat('en-US', {style: 'percent'})

export function CampaignProgressBar({
  openCount = 0,
  closedCount = 0,
  openWithLinksCount = 0,
}: CampaignProgressBarProps): JSX.Element {
  const totalCount = openCount + closedCount
  const fractionAlertsClosed = totalCount === 0 ? 0 : closedCount / totalCount
  const formattedPercentAlertsClosed = percentFormatter.format(fractionAlertsClosed)

  // Alerts that have links are considered in-progress
  const fractionAlertsInProgress = totalCount === 0 ? 0 : openWithLinksCount / totalCount
  const formattedPercentAlertsInProgress = percentFormatter.format(fractionAlertsInProgress)

  return (
    <Stack gap="none">
      <p className="text-small fgColor-muted my-1">
        {formattedPercentAlertsClosed} closed ({totalCount} {pluralize('alert', totalCount)})
      </p>
      <ProgressBar
        inline
        aria-label="Campaign progress"
        aria-valuetext={`${formattedPercentAlertsClosed} alerts closed, ${formattedPercentAlertsInProgress} in progress`}
        className={styles.ProgressBar}
      >
        {fractionAlertsClosed > 0 && (
          <ProgressBar.Item
            aria-label="Campaign alerts closed"
            progress={fractionAlertsClosed * 100}
            role="progressbar"
            aria-valuenow={fractionAlertsClosed * 100}
            className={styles.Closed}
          />
        )}
        {fractionAlertsInProgress > 0 && (
          <ProgressBar.Item
            aria-label="Campaign alerts in progress"
            progress={fractionAlertsInProgress * 100}
            role="progressbar"
            aria-valuenow={fractionAlertsInProgress * 100}
            className={styles.InProgress}
          />
        )}
      </ProgressBar>
    </Stack>
  )
}
