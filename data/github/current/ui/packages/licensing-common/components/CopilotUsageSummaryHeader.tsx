import {Stack} from '@primer/react'
import {clsx} from 'clsx'
import styles from './CopilotUsageSummaryHeader.module.css'

import {CopilotUsageHint} from './CopilotUsageHint'

export interface CopilotUsageSummaryHeaderProps {
  title: string
  description?: string
  children?: React.ReactNode
  headingLevel?: 'h2' | 'h3'
}

export function CopilotUsageSummaryHeader({
  title,
  description,
  children,
  headingLevel,
}: CopilotUsageSummaryHeaderProps) {
  const HeadingTag = headingLevel as keyof JSX.IntrinsicElements // Dynamically set the heading tag

  return (
    <Stack
      className={clsx(styles.usageSummaryHeader)}
      direction="horizontal"
      gap="condensed"
      padding="none"
      align="center"
    >
      <HeadingTag data-testid="usage-summary-header-title" className={'h5'}>
        {title}
      </HeadingTag>
      <CopilotUsageHint title={title} description={description}>
        {children}
      </CopilotUsageHint>
    </Stack>
  )
}
