import {ProgressBar, Stack, Text} from '@primer/react'
import pluralize from 'pluralize'

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
      <Text sx={{paddingY: 0, marginY: 0}}>
        {formattedPercentAlertsClosed} closed ({totalCount} {pluralize('alert', totalCount)})
      </Text>
      <ProgressBar
        inline
        sx={{minWidth: '12vw'}}
        aria-label="Campaign progress"
        aria-valuetext={`${formattedPercentAlertsClosed} alerts closed, ${formattedPercentAlertsInProgress} in progress`}
      >
        {fractionAlertsClosed > 0 && (
          <ProgressBar.Item
            aria-label="Campaign alerts closed"
            progress={fractionAlertsClosed * 100}
            sx={{backgroundColor: 'done.emphasis'}}
            role="progressbar"
            aria-valuenow={fractionAlertsClosed * 100}
          />
        )}
        {fractionAlertsInProgress > 0 && (
          <ProgressBar.Item
            aria-label="Campaign alerts in progress"
            progress={fractionAlertsInProgress * 100}
            sx={{backgroundColor: 'neutral.emphasis'}}
            role="progressbar"
            aria-valuenow={fractionAlertsInProgress * 100}
          />
        )}
      </ProgressBar>
    </Stack>
  )
}
