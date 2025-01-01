import DataCard from '@github-ui/data-card'
import {LoadingSkeleton} from '@github-ui/skeleton/LoadingSkeleton'
import {Link} from '@primer/react'
import pluralize from 'pluralize'

export interface AutofixMetricProps {
  count: number
  isLoading: boolean
}

export function AutofixMetric({count, isLoading}: AutofixMetricProps) {
  if (isLoading) {
    return (
      <DataCard cardTitle="Copilot Autofix">
        <LoadingSkeleton variant="rounded" height="30px" width="80%" mb="8px" />
        <LoadingSkeleton variant="rounded" height="12px" width="100%" mb="2px" />
        <LoadingSkeleton variant="rounded" height="12px" width="100%" />
        <LoadingSkeleton variant="rounded" height="12px" width="60%" />
      </DataCard>
    )
  }

  return (
    <DataCard cardTitle="Copilot Autofix">
      <DataCard.Counter count={count} metric={`supported ${pluralize('alert', count)}`} />
      <DataCard.Description>
        Copilot Autofix will try to suggest fixes for the supported alerts. Read more about&nbsp;
        <Link
          inline
          href="https://docs.github.com/en/code-security/code-scanning/managing-code-scanning-alerts/about-autofix-for-codeql-code-scanning"
        >
          Copilot Autofix.
        </Link>
      </DataCard.Description>
    </DataCard>
  )
}
