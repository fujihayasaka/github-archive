import DataCard from '@github-ui/data-card'
import {number as formatNumber} from '@github-ui/formatters'
import {Stack} from '@primer/react'

export interface AutofixStatsMetricProps {
  generatedCount: number
  appliedCount: number
}

export function AutofixStatsMetric({generatedCount, appliedCount}: AutofixStatsMetricProps) {
  const alertCountTextClasses = 'f3'
  const alertDescriptionTextClasses = 'f4 fgColor-muted'
  return (
    <DataCard cardTitle="Fixed alerts using Copilot Autofix" sx={{width: '100%'}}>
      <div className="d-flex">
        <Stack direction="horizontal" justify="space-between" gap="condensed" align="baseline">
          <span className={alertCountTextClasses}>{formatNumber(appliedCount)}</span>
          <span className={alertDescriptionTextClasses}>out of</span>
          <span className={alertDescriptionTextClasses}>{formatNumber(generatedCount)}</span>
          <span className={alertDescriptionTextClasses}>generated</span>
        </Stack>
      </div>
      <DataCard.Description>
        Merged pull requests with Copilot Autofix in all campaigns using at least 50% of the suggested code.
      </DataCard.Description>
    </DataCard>
  )
}
