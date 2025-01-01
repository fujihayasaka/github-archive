import {Stack, Text} from '@primer/react'
import {clsx} from 'clsx'
import styles from './CopilotUsageSummaryItem.module.css'

export interface CopilotUsageSummaryItemProps {
  sku: string
  consumedLicenses: number
}

export function CopilotUsageSummaryItem({sku, consumedLicenses}: CopilotUsageSummaryItemProps) {
  const capitalizedName = sku.charAt(0).toUpperCase() + sku.slice(1)

  return (
    <Stack
      direction="vertical"
      gap="condensed"
      padding="none"
      className={clsx(styles.fillWidth)}
      data-testid="usage-summary-item"
    >
      <Text className={clsx('f3', styles.lineHeightSpacious)} size="medium" data-testid="summary-item-amount">
        {consumedLicenses.toLocaleString()}
      </Text>

      <Text className="color-fg-muted" size="medium" data-testid="summary-amount-desc">
        {capitalizedName} licenses
      </Text>
    </Stack>
  )
}
