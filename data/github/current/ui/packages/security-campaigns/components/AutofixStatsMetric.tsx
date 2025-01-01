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
    <DataCard cardTitle="Copilot Autofix">
      <div className="d-flex">
        <Stack direction="vertical" justify="space-between" gap="none" align="baseline">
          <Stack direction="horizontal" justify="space-between" gap="condensed" align="baseline">
            <span className={alertCountTextClasses}>{formatNumber(appliedCount)}</span>
            <span className={alertDescriptionTextClasses}>fixed by Copilot Autofix</span>
          </Stack>
          <Stack direction="horizontal" justify="space-between" gap="condensed" align="baseline">
            <span className={alertCountTextClasses}>{formatNumber(generatedCount)}</span>
            <span className={alertDescriptionTextClasses}>Copilot Autofixes generated</span>
          </Stack>
        </Stack>
      </div>
      <DataCard.Description>
        Number of alerts fixed with a Copilot Autofix out of all alerts where a fix was suggested.
      </DataCard.Description>
    </DataCard>
  )
}
