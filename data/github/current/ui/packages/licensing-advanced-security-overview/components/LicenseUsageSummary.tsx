import {LicenseUsageSummaryItem} from './LicenseUsageSummaryItem'
import {LicenseUsageSummaryHeader} from './LicenseUsageSummaryHeader'
import type {Sku} from '../utils'
import {Stack, Link} from '@primer/react'
import {clsx} from 'clsx'
import styles from './LicenseUsageSummary.module.css'

export interface LicenseUsageSummaryProps {
  isVolumeLicensed: boolean
  skus: Sku[]
  unlimitedLicense: boolean
}

export function LicenseUsageSummary({isVolumeLicensed, skus, unlimitedLicense}: LicenseUsageSummaryProps) {
  return (
    <Stack direction="vertical" gap="none" padding="none" align="start" className={clsx(styles.mainWrapper)}>
      <LicenseUsageSummaryHeader
        title="Consumed licenses"
        description="Active committers who contributed to at least one private organization-owned or user-owned repository."
      >
        <Link
          href="https://docs.github.com/en/enterprise-cloud@latest/billing/managing-billing-for-your-products/managing-billing-for-github-advanced-security/about-billing-for-github-advanced-security#understanding-usage"
          data-testid="seat-count-learn-more-link"
        >
          Learn more
        </Link>
      </LicenseUsageSummaryHeader>
      <Stack direction="horizontal" gap="condensed" padding="none" className={clsx(styles.childrenWrapper)}>
        {skus.map(sku => (
          <LicenseUsageSummaryItem
            consumedLicenses={sku.consumedLicenses}
            description={sku.name}
            purchasedLicenses={sku.purchasedLicenses}
            isVolumeLicensed={isVolumeLicensed}
            key={sku.sku}
            unlimitedLicense={unlimitedLicense}
          />
        ))}
      </Stack>
    </Stack>
  )
}
