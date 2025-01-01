import DataCard from '@github-ui/data-card'
import {ArrowUpIcon} from '@primer/octicons-react'
import {useMemo} from 'react'

import rawStyles from './AlertsRemediatedCard.module.css'
import useAlertsFixedQuery, {type UseAlertsFixedQueryParams} from './use-alerts-fixed-query'

const styles = rawStyles as Record<string, string>

interface AlertsFixedCardProps extends UseAlertsFixedQueryParams {
  title?: string
}

interface ComputedValues {
  computedDependabotFixed: number
  computedManualFixed: number
  computedDependabotPercentage: number
  computedManualPercentage: number
}

export default function AlertsRemediatedCard(props: AlertsFixedCardProps): JSX.Element {
  const dataQuery = useAlertsFixedQuery(props)

  const {
    computedDependabotFixed: dependabotFixed,
    computedManualFixed: manualFixed,
    computedDependabotPercentage: dependabotPercentage,
    computedManualPercentage: manualPercentage,
  } = useMemo<ComputedValues>(() => {
    if (!dataQuery.isSuccess) {
      return {
        computedDependabotFixed: 0,
        computedManualFixed: 0,
        computedDependabotPercentage: 0,
        computedManualPercentage: 100,
      }
    }

    // Safely cast dataQuery.data to a known type
    const safeData = dataQuery.data as {matching: number; count: number; percentage: number}
    const matchingAlerts = safeData.matching
    const computedDependabotFixed = safeData.count
    const computedManualFixed = matchingAlerts - computedDependabotFixed

    const computedDependabotPercentage = (computedDependabotFixed / matchingAlerts) * 100
    const computedManualPercentage = (computedManualFixed / matchingAlerts) * 100

    return {computedDependabotFixed, computedManualFixed, computedDependabotPercentage, computedManualPercentage}
  }, [dataQuery])

  return (
    <DataCard cardTitle="Alerts remediated" loading={dataQuery.isPending} error={dataQuery.isError}>
      {dataQuery.isSuccess &&
        ((): JSX.Element => {
          // Explicitly cast dataQuery.data in the render block
          const safeData = dataQuery.data as {matching: number; count: number; percentage: number}
          return (
            <>
              {/* Percentage increase indicator */}
              <div className={styles.counterContainer}>
                <ArrowUpIcon size={16} />
                <span className={styles.percentageText}>{safeData.percentage}% last 30 days</span>
              </div>

              {/* Matching alerts count */}
              <h2 className={styles.matchingAlertsText}>{safeData.matching} alerts</h2>

              {/* Progress bar - Dependabot (Blue) | Manual (Pink) */}
              <DataCard.ProgressBar
                data={[
                  {
                    progress: dependabotPercentage,
                    color: 'accent.fg',
                    label: '',
                  },
                  {
                    progress: manualPercentage,
                    color: 'danger.fg',
                    label: '',
                  },
                ]}
              />

              {/* Dependabot and Manual Counts - Inline */}
              <div className={styles.inlineCounts}>
                <span className={styles.countText}>
                  {dependabotFixed} <span className={styles.mutedText}>fixed by Dependabot</span>
                </span>
                <span className={styles.countText}>
                  {manualFixed} <span className={styles.mutedText}>manual</span>
                </span>
              </div>
            </>
          )
        })()}
    </DataCard>
  )
}
