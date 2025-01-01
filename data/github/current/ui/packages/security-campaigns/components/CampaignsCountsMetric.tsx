import DataCard from '@github-ui/data-card'
import {DotFillIcon} from '@primer/octicons-react'
import {Stack} from '@primer/react'
import {number as formatNumber} from '@github-ui/formatters'
import pluralize from 'pluralize'

import styles from './CampaignsCountsMetric.module.css'

export interface CampaignsCountsMetricProps {
  title: string
  description: React.ReactNode
  campaignsCount: number
  totalAlertCount: number
  openAlertsCount: number
  fixedAlertsCount: number
  dismissedAlertsCount: number
  inProgressAlertsCount?: number
}

export function CampaignsCountsMetric({
  title,
  description,
  totalAlertCount,
  openAlertsCount,
  fixedAlertsCount,
  dismissedAlertsCount,
  inProgressAlertsCount,
}: CampaignsCountsMetricProps) {
  const openAlertsColor = 'success.emphasis'
  const openAlertsColorClass = 'color-fg-success'
  const inProgressAlertsColor = 'neutral.emphasis'
  const inProgressAlertsColorClass = 'color-fg-muted'
  const fixedAlertsColor = 'done.emphasis'
  const fixedAlertsColorClass = 'color-fg-success'
  const dismissedAlertsColor = 'danger.emphasis'
  const dismissedAlertsColorClass = 'color-fg-danger'

  const progressBarData = []

  if (openAlertsCount > 0) {
    progressBarData.push({
      progress: calculatePercentage(totalAlertCount, openAlertsCount),
      color: openAlertsColor,
      label: `${formatNumber(openAlertsCount)} Open`,
    })
  }

  if (inProgressAlertsCount !== undefined && inProgressAlertsCount > 0) {
    progressBarData.push({
      progress: calculatePercentage(totalAlertCount, inProgressAlertsCount),
      color: inProgressAlertsColor,
      label: `${formatNumber(inProgressAlertsCount)} In progress`,
    })
  }

  if (fixedAlertsCount > 0) {
    progressBarData.push({
      progress: calculatePercentage(totalAlertCount, fixedAlertsCount),
      color: fixedAlertsColor,
      label: `${formatNumber(fixedAlertsCount)} Fixed`,
    })
  }

  if (dismissedAlertsCount > 0) {
    progressBarData.push({
      progress: calculatePercentage(totalAlertCount, dismissedAlertsCount),
      color: dismissedAlertsColor,
      label: `${formatNumber(dismissedAlertsCount)} Dismissed`,
    })
  }

  const progresBarDescription = buildProgressBarDescription(
    openAlertsCount,
    fixedAlertsCount,
    dismissedAlertsCount,
    inProgressAlertsCount,
  )

  return (
    <DataCard cardTitle={title} sx={{width: '100%'}}>
      <Stack direction="horizontal">
        <Stack direction="horizontal" justify="space-between" gap="condensed" align="baseline">
          <span className={styles.totalAlertCountText}>{formatNumber(totalAlertCount)}</span>
          <span className={styles.campaignCountText}>total {pluralize('alert', totalAlertCount)}</span>
        </Stack>
      </Stack>
      <DataCard.ProgressBar data={progressBarData} aria-label={progresBarDescription} />
      <DataCard.Description>
        <span className="d-flex flex-wrap pb-2">
          <LegendItem colorClass={openAlertsColorClass} label={`${formatNumber(openAlertsCount)} open`} />
          {inProgressAlertsCount !== undefined && (
            <LegendItem
              colorClass={inProgressAlertsColorClass}
              label={`${formatNumber(inProgressAlertsCount)} in progress`}
            />
          )}
          <LegendItem colorClass={fixedAlertsColorClass} label={`${formatNumber(fixedAlertsCount)} fixed`} />
          <LegendItem
            colorClass={dismissedAlertsColorClass}
            label={`${formatNumber(dismissedAlertsCount)} dismissed`}
          />
        </span>
        {description}
      </DataCard.Description>
    </DataCard>
  )
}

const LegendItem = ({colorClass, label}: {colorClass: string; label: string}) => {
  return (
    <span className="mr-2">
      <span className={colorClass}>
        <DotFillIcon />
      </span>
      {label}
    </span>
  )
}

const buildProgressBarDescription = (
  openAlertsCount: number,
  fixedAlertsCount: number,
  dismissedAlertsCount: number,
  inProgressAlertsCount?: number,
) => {
  const inProgressText =
    inProgressAlertsCount !== undefined ? `, ${formatNumber(inProgressAlertsCount)} in progress` : ''
  return `${formatNumber(openAlertsCount)} open${inProgressText}, ${formatNumber(
    fixedAlertsCount,
  )} fixed, ${formatNumber(dismissedAlertsCount)} dismissed`
}

const calculatePercentage = (total: number, count: number) => {
  return total === 0 ? 0 : (count / total) * 100
}
