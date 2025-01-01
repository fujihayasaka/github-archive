import DataCard from '@github-ui/data-card'
import {useMemo} from 'react'

import usePullRequestAlertsFixedWithAutofixQuery, {
  type UsePullRequestAlertsFixedWithAutofixQueryParams,
} from './use-pull-request-alerts-fixed-with-autofix-query'

interface AlertsFixedWithAutofixCardProps extends UsePullRequestAlertsFixedWithAutofixQueryParams {}

export default function PullRequestAlertsFixedWithAutofixCard(props: AlertsFixedWithAutofixCardProps): JSX.Element {
  const dataQuery = usePullRequestAlertsFixedWithAutofixQuery(props)

  const [percentageAccepted, percentageNotAccepted] = useMemo(() => {
    if (!dataQuery.isSuccess) return [0, 100]
    if (dataQuery.data.suggested === 0) return [0, 100]

    const accepted = (100 * dataQuery.data.accepted) / dataQuery.data.suggested
    return [accepted, 100 - accepted]
  }, [dataQuery])

  return (
    <DataCard
      as="h3"
      cardTitle="CodeQL pull request alerts fixed with autofix suggestions"
      loading={dataQuery.isPending}
      error={dataQuery.isError}
    >
      {dataQuery.isSuccess && (
        <>
          <DataCard.Counter count={dataQuery.data.accepted} total={dataQuery.data.suggested} />
          <DataCard.ProgressBar
            data={[
              {
                progress: percentageAccepted,
                color: 'success.emphasis',
                label: `${percentageAccepted} of autofix suggestions were accepted`,
              },
              {
                progress: percentageNotAccepted,
                color: 'accent.emphasis',
                label: `${percentageNotAccepted} of autofix suggestions were not accepted`,
              },
            ]}
          />
          <DataCard.Description>
            Total CodeQL vulnerabilities fixed with an accepted autofix out of all with a suggested autofix
          </DataCard.Description>
        </>
      )}
    </DataCard>
  )
}
