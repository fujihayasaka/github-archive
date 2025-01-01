import type {RangeSelection} from '@github-ui/date-picker'
import {addUrlToHistoryStack} from '@github-ui/history'
import {Heading} from '@primer/react'
import {TabNav} from '@primer/react/deprecated'
import {Stack} from '@primer/react/experimental'
import {useEffect, useMemo, useState} from 'react'

import {isRangeSelection} from '../../common/components/date-span-picker'
import type {CustomProperty} from '../../common/filter-providers/types'
import type {Period} from '../../common/utils/date-period'
import {AdvisoriesTable} from './advisories-table/AdvisoriesTable'
import {AgeOfAlertsCard} from './age-of-alerts-card/AgeOfAlertsCard'
import {AlertTrendsChart} from './alert-trends-chart/AlertTrendsChart'
import type {GroupingType} from './alert-trends-chart/grouping-type'
import styles from './DetectionView.module.css'
import {ReopenedAlertsCard} from './reopened-alerts-card/ReopenedAlertsCard'
import {RepositoriesTable} from './repositories-table/RepositoriesTable'
import {SastTable} from './sast-table/SastTable'
import {SecretsBypassedCard} from './secrets-bypassed/SecretsBypassedCard'

type ImpactAnalysisTab = 'repositories' | 'advisories' | 'sast'

export interface DetectionViewProps {
  submittedQuery: string
  startDateString: string
  endDateString: string
  selectedDateSpan: Period | RangeSelection
  customProperties: CustomProperty[]
  alertTrendsGrouping?: GroupingType
  initialSelectedImpactAnalysisTable: ImpactAnalysisTab
}

export function DetectionView({
  submittedQuery,
  startDateString,
  endDateString,
  selectedDateSpan,
  customProperties,
  alertTrendsGrouping,
  initialSelectedImpactAnalysisTable,
}: DetectionViewProps): JSX.Element {
  // track selected impact analysis tabnav state
  const [selectedTable, setSelectedTable] = useState<ImpactAnalysisTab>(initialSelectedImpactAnalysisTable)

  // Change the URL.
  useEffect(() => {
    const url = new URL(window.location.href, window.location.origin)
    const nextParams = url.searchParams

    if (selectedTable !== 'repositories') {
      nextParams.set('impactAnalysisTab', selectedTable)
    } else {
      nextParams.delete('impactAnalysisTab')
    }

    addUrlToHistoryStack(`${url.pathname}${url.search}`)
  }, [selectedTable])

  const cardProps = useMemo(() => {
    return {
      query: submittedQuery,
      startDate: startDateString,
      endDate: endDateString,
    }
  }, [submittedQuery, startDateString, endDateString])

  return (
    <Stack direction="vertical">
      <AlertTrendsChart
        isOpenSelected
        query={submittedQuery}
        startDate={startDateString}
        endDate={endDateString}
        grouping={alertTrendsGrouping}
      />
      <Stack direction="horizontal" wrap="wrap">
        <AgeOfAlertsCard {...cardProps} />
        <ReopenedAlertsCard {...cardProps} />
        <SecretsBypassedCard
          query={submittedQuery}
          customProperties={customProperties}
          startDate={startDateString}
          endDate={endDateString}
          datePeriod={isRangeSelection(selectedDateSpan) ? undefined : selectedDateSpan}
        />
      </Stack>
      <Stack direction="vertical" gap="none">
        <Heading as="h3" className={styles.DetectionViewImpactHeading}>
          Impact analysis
        </Heading>
        <p>Top 10 repositories and vulnerabilities that pose the biggest impact on your application security.</p>
        <TabNav aria-label="Impact Analysis" className={styles.TabNav}>
          <TabNav.Link
            as="button"
            onClick={() => setSelectedTable('repositories')}
            selected={selectedTable === 'repositories'}
          >
            Repositories
          </TabNav.Link>
          <TabNav.Link
            as="button"
            onClick={() => setSelectedTable('advisories')}
            selected={selectedTable === 'advisories'}
          >
            Advisories
          </TabNav.Link>
          <TabNav.Link as="button" onClick={() => setSelectedTable('sast')} selected={selectedTable === 'sast'}>
            SAST vulnerabilities
          </TabNav.Link>
        </TabNav>
        {selectedTable === 'repositories' && <RepositoriesTable {...cardProps} />}
        {selectedTable === 'advisories' && <AdvisoriesTable {...cardProps} />}
        {selectedTable === 'sast' && <SastTable {...cardProps} />}
      </Stack>
    </Stack>
  )
}
