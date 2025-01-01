import type {Sku} from '../copilot-types'
import {Stack, Link} from '@primer/react'
import {clsx} from 'clsx'
import styles from './CopilotUsageSummary.module.css'

import {CopilotUsageSummaryItem} from './CopilotUsageSummaryItem'
import {CopilotUsageSummaryHeader} from './CopilotUsageSummaryHeader'

export interface CopilotUsageSummaryProps {
  skus: Sku[]
}

export function CopilotUsageSummary({skus}: CopilotUsageSummaryProps) {
  const description =
    skus.length === 1
      ? skus[0] && `Unique licenses assigned for Copilot ${skus[0].sku.charAt(0).toUpperCase() + skus[0].sku.slice(1)}.`
      : 'Unique licenses assigned for Copilot Business and Copilot Enterprise.'

  return (
    <Stack direction="vertical" gap="none" padding="none" align="start" className={clsx(styles.mainWrapper)}>
      <CopilotUsageSummaryHeader title="Consumed licenses" description={description}>
        <Link
          href="https://docs.github.com/en/copilot/about-github-copilot/subscription-plans-for-github-copilot"
          data-testid="seat-count-learn-more-link"
        >
          Learn more
        </Link>
      </CopilotUsageSummaryHeader>
      <Stack direction="horizontal" gap="condensed" padding="none" className={clsx(styles.childrenWrapper)}>
        {skus.map(sku => (
          <CopilotUsageSummaryItem {...sku} key={sku.sku} />
        ))}
      </Stack>
    </Stack>
  )
}
