import {Stack} from '@primer/react'
import {clsx} from 'clsx'
import styles from './CopilotUsageSummaryHeader.module.css'

import {CopilotUsageHint} from './CopilotUsageHint'

export interface CopilotUsageSummaryHeaderProps {
  title: string
  description?: string
  children?: React.ReactNode
}

export function CopilotUsageSummaryHeader({title, description, children}: CopilotUsageSummaryHeaderProps) {
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
      <CopilotUsageHint title={title} description={description}>
        {children}
      </CopilotUsageHint>
    </Stack>
  )
}
