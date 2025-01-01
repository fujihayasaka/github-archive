import {Heading, Stack} from '@primer/react'
import type {HeadingTag} from '../types/heading-tag'
import {clsx} from 'clsx'
import styles from './UsageSummary.module.css'

export interface UsageSummaryProps {
  title: string
  headingAs?: HeadingTag
  usageHint?: React.ReactNode
  children?: React.ReactNode
}

export function UsageSummary({headingAs = 'h3', title, usageHint, children}: UsageSummaryProps) {
  return (
    <Stack direction="vertical" gap="none" padding="none" align="start" className={clsx(styles.mainWrapper)}>
      <Stack
        className={clsx(styles.usageSummaryHeader)}
        direction="horizontal"
        gap="condensed"
        padding="none"
        align="center"
      >
        <Heading as={headingAs} data-testid="usage-summary-header-title" className={'f5'}>
          {title}
        </Heading>
        {usageHint !== undefined && usageHint}
      </Stack>
      {children}
    </Stack>
  )
}
