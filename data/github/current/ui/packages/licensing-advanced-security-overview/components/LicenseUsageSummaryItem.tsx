import {Stack, Text} from '@primer/react'
import {clsx} from 'clsx'
import styles from './LicenseUsageSummaryItem.module.css'
import {LicenseUsageProgressBar} from './LicenseUsageProgressBar'

export interface LicenseUsageSummaryItemProps {
  consumedLicenses: number
  description?: string
  isTrial?: boolean
  isVolumeLicensed?: boolean
  purchasedLicenses: number
  unlimitedLicense: boolean
}

export function LicenseUsageSummaryItem({
  consumedLicenses,
  description,
  isTrial,
  isVolumeLicensed,
  purchasedLicenses,
  unlimitedLicense,
}: LicenseUsageSummaryItemProps) {
  const showAvailableLicenses = isTrial || (isVolumeLicensed && purchasedLicenses !== 0 && !unlimitedLicense)
  return (
    <Stack
      direction="vertical"
      gap="condensed"
      padding="none"
      className={clsx(styles.fillWidth)}
      data-testid="license-usage-summary-item"
    >
      <Stack direction="horizontal" gap="normal" padding="none" align="baseline" justify="space-between">
        <Text className="f3 lh-default" size="medium" weight="normal" data-testid="summary-item-amount">
          {consumedLicenses?.toLocaleString()}
        </Text>
        {showAvailableLicenses && (
          <Text className="color-fg-muted" size="medium" data-testid="available-licenses-count">
            {purchasedLicenses.toLocaleString()} available
          </Text>
        )}
      </Stack>

      {isVolumeLicensed && (
        <LicenseUsageProgressBar consumedLicenses={consumedLicenses} purchasedLicenses={purchasedLicenses} />
      )}
      <Text className="color-fg-muted" size="small" data-testid="summary-amount-desc">
        {description}
      </Text>
    </Stack>
  )
}
