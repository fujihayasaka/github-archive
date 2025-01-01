import {Stack} from '@primer/react'
import {clsx} from 'clsx'
import styles from './LicenseUsageSummaryHeader.module.css'
import {LicenseUsageHint} from './LicenseUsageHint'

export interface LicenseUsageSummaryHeaderProps {
  title: string
  description: string
  children?: React.ReactNode
}

export function LicenseUsageSummaryHeader({title, description, children}: LicenseUsageSummaryHeaderProps) {
  return (
    <Stack
      className={clsx(styles.usageSummaryHeader)}
      direction="horizontal"
      gap="condensed"
      padding="none"
      align="center"
    >
      <h4 className="f5" data-testid="usage-summary-header-title">
        {title}
      </h4>
      <LicenseUsageHint title={title} description={description}>
        {children}
      </LicenseUsageHint>
    </Stack>
  )
}
