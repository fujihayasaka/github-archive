import DataCard from '@github-ui/data-card'
import {DotFillIcon} from '@primer/octicons-react'
import {Box, Text, Stack} from '@primer/react'
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
  campaignsCount,
  totalAlertCount,
  openAlertsCount,
  fixedAlertsCount,
  dismissedAlertsCount,
  inProgressAlertsCount,
}: CampaignsCountsMetricProps) {
  const openAlertsColor = 'success.emphasis'
  const inProgressAlertsColor = 'neutral.emphasis'
  const fixedAlertsColor = 'done.emphasis'
  const dismissedAlertsColor = 'danger.emphasis'

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
    <DataCard cardTitle={title}>
      <Box sx={{display: 'flex'}}>
        <Stack direction="horizontal" justify="space-between" gap="condensed" align="baseline">
          <span className={styles.totalAlertCountText}>
            {formatNumber(totalAlertCount)} {pluralize('alert', totalAlertCount)}
          </span>
          <span className={styles.campaignCountText}>
            in {formatNumber(campaignsCount)} {pluralize('campaign', campaignsCount)}
          </span>
        </Stack>
      </Box>
      <DataCard.ProgressBar data={progressBarData} aria-label={progresBarDescription} />
      <DataCard.Description>
        <Box sx={{display: 'flex', mb: 2}} as="span">
          <Text weight="medium">
            <LegendItem color={openAlertsColor} label={`${formatNumber(openAlertsCount)} open`} />
            {inProgressAlertsCount !== undefined && (
              <LegendItem color={inProgressAlertsColor} label={`${formatNumber(inProgressAlertsCount)} in progress`} />
            )}
            <LegendItem color={fixedAlertsColor} label={`${formatNumber(fixedAlertsCount)} fixed`} />
            <LegendItem color={dismissedAlertsColor} label={`${formatNumber(dismissedAlertsCount)} dismissed`} />
          </Text>
        </Box>
        {description}
      </DataCard.Description>
    </DataCard>
  )
}

const LegendItem = ({color, label}: {color: string; label: string}) => {
  return (
    <Box sx={{mr: 2}} as="span">
      <Box sx={{color}} as="span">
        <DotFillIcon />
      </Box>
      {label}
    </Box>
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
