import type {FilterProvider} from '@github-ui/filter'
import {addUrlToHistoryStack} from '@github-ui/history'
import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import {useSso} from '@github-ui/use-sso'
import {Stack} from '@primer/react/experimental'
import {parseISO} from 'date-fns'
import {useEffect, useMemo, useState} from 'react'

import {type DateSpan, dateSpansAreEqual, isRangeSelection, toDateSpan} from '../common/components/date-span-picker'
import {ExportBanner} from '../common/components/export-banner/ExportBanner'
import PageLayout from '../common/components/page-layout'
import {usePaths} from '../common/contexts/Paths'
import {useDirtyStateTracking} from '../common/hooks/use-dirty-state-tracking'
import {toUTCDateString} from '../common/utils/date-formatter'
import {calculateDateRangeFromPeriod, type Period} from '../common/utils/date-period'
import AlertsFixedCard from './components/alerts-fixed-card/AlertsFixedCard'
import AlertsFixedWithAutofixCard from './components/alerts-fixed-with-autofix-card/AlertsFixedWithAutofixCard'
import AlertsFoundCard from './components/alerts-found-card/AlertsFoundCard'
import AlertsTimechartCard from './components/alerts-timechart-card/AlertsTimechartCard'
import AutofixSuggestionsCard from './components/autofix-suggestions-card/AutofixSuggestionsCard'
import MostPrevalentRulesCard from './components/most-prevalent-rules-card/MostPrevalentRulesCard'
import RemediationRatesCard from './components/remediation-rates/RemediationRatesCard'
import RemediationTimeTile from './components/remediation-time/RemediationTimeTile'
import RepositoriesTable from './components/repositories-table/RepositoriesTable'

export interface SecurityCenterCodeScanningMetricsProps {
  initialQuery?: string
  initialDateSpan?: Period | {from: string; to: string}
  watermarkDate?: string
  feedbackLink: {
    text: string
    url: string
  }
  showIncompleteDataWarning: boolean
  incompleteDataWarningDocHref: string
  exportErrorMessage?: string
  filterProviders: FilterProvider[]
  allowAutofixFeatures: boolean
  allowCsvExport: boolean
  allowAutofixRemediationTimeTile: boolean
}

const DEFAULT_QUERY: string = 'archived:false'
export const DEFAULT_DATE_SPAN: Period = {period: 'last90days'}

export function SecurityCenterCodeScanningMetrics({
  initialQuery,
  initialDateSpan,
  watermarkDate,
  feedbackLink,
  showIncompleteDataWarning,
  incompleteDataWarningDocHref,
  exportErrorMessage,
  filterProviders,
  allowAutofixFeatures,
  allowCsvExport,
  allowAutofixRemediationTimeTile,
}: SecurityCenterCodeScanningMetricsProps): JSX.Element {
  // prepare SSO org names for banner
  const {ssoOrgs} = useSso()
  const ssoOrgNames = ssoOrgs.map(o => o['login']).filter(n => n !== undefined)

  // track selected filter state
  const [query, setQuery] = useState<string>(initialQuery ?? DEFAULT_QUERY)
  const [queryIsDirty, resetQueryIsDirty] = useDirtyStateTracking(query, DEFAULT_QUERY, !!initialQuery)

  // track selected date span state
  const [dateSpan, setDateSpan] = useState<DateSpan>(() =>
    initialDateSpan != null ? toDateSpan(initialDateSpan) : DEFAULT_DATE_SPAN,
  )
  const [dateSpanIsDirty, resetDateSpanIsDirty] = useDirtyStateTracking(
    dateSpan,
    DEFAULT_DATE_SPAN,
    !!initialDateSpan,
    dateSpansAreEqual,
  )

  // keep browser URL in sync with selected trend grouping
  useEffect(() => {
    const url = new URL(window.location.href, window.location.origin)
    const nextParams = url.searchParams

    if (queryIsDirty) {
      nextParams.set('query', query)
    } else {
      nextParams.delete('query')
    }

    if (dateSpanIsDirty) {
      if (isRangeSelection(dateSpan)) {
        nextParams.set('startDate', toUTCDateString(dateSpan.from))
        nextParams.set('endDate', toUTCDateString(dateSpan.to))
        nextParams.delete('period')
      } else {
        nextParams.set('period', dateSpan.period)
        nextParams.delete('startDate')
        nextParams.delete('endDate')
      }
    } else {
      nextParams.delete('period')
      nextParams.delete('startDate')
      nextParams.delete('endDate')
    }

    addUrlToHistoryStack(`${url.pathname}${url.search}`)
  }, [query, queryIsDirty, dateSpan, dateSpanIsDirty])

  const cardProps = useMemo(() => {
    const dateRange = isRangeSelection(dateSpan) ? dateSpan : calculateDateRangeFromPeriod(dateSpan)
    return {
      query,
      startDate: toUTCDateString(dateRange.from),
      endDate: toUTCDateString(dateRange.to),
      allowAutofixFeatures,
    }
  }, [query, dateSpan, allowAutofixFeatures])

  const paths = usePaths()
  const startedBannerId = 'security-center-export-started-banner'
  const successBannerId = 'security-center-export-success-banner'
  const errorBannerId = 'security-center-export-error-banner'

  return (
    <PageLayout>
      <PageLayout.Banners>
        {ssoOrgNames.length > 0 && <SingleSignOnBanner protectedOrgs={ssoOrgNames} data-testid="sso-banner" />}

        {allowCsvExport && (
          <>
            <ExportBanner id={startedBannerId} type="accent" />
            <ExportBanner id={successBannerId} type="success" />
            <ExportBanner id={errorBannerId} type="danger" errorMessage={exportErrorMessage} />
          </>
        )}
      </PageLayout.Banners>

      <PageLayout.Header
        title="CodeQL pull request alerts"
        description="A report of vulnerabilities prevented by CodeQL, caught in pull requests that have been merged to the default branch"
        feedbackLink={feedbackLink}
      />

      <PageLayout.FilterBar
        filter={<PageLayout.Filter providers={filterProviders} query={query} onSubmit={setQuery} />}
        datePicker={
          <PageLayout.DatePicker
            value={dateSpan}
            onChange={setDateSpan}
            watermarkDate={watermarkDate ? parseISO(watermarkDate) : undefined}
          />
        }
        revert={
          <PageLayout.FilterRevert
            show={queryIsDirty || dateSpanIsDirty}
            onRevert={() => {
              setQuery(DEFAULT_QUERY)
              resetQueryIsDirty()
              setDateSpan(DEFAULT_DATE_SPAN)
              resetDateSpanIsDirty()
            }}
          />
        }
      />

      {allowCsvExport && (
        <PageLayout.ExportButton
          exportUrl={paths.codeScanningCsvExportPath({...cardProps})}
          startedBannerId={startedBannerId}
          successBannerId={successBannerId}
          errorBannerId={errorBannerId}
        />
      )}

      <PageLayout.LimitedRepoWarning show={showIncompleteDataWarning} href={incompleteDataWarningDocHref} />

      <PageLayout.Content>
        <Stack direction={'vertical'}>
          <Stack direction={'horizontal'} wrap={'wrap'}>
            <AlertsFoundCard {...cardProps} />
            {allowAutofixFeatures && <AutofixSuggestionsCard {...cardProps} />}
            <AlertsFixedCard {...cardProps} />
          </Stack>

          <AlertsTimechartCard {...cardProps} />

          <Stack direction={'horizontal'} wrap={'wrap'}>
            {allowAutofixFeatures && (
              <Stack.Item grow>
                <Stack direction={'vertical'}>
                  <Stack direction={'horizontal'}>
                    <AlertsFixedWithAutofixCard {...cardProps} />
                  </Stack>
                  <Stack direction={'horizontal'}>
                    <RemediationRatesCard {...cardProps} />
                  </Stack>
                  {allowAutofixRemediationTimeTile && (
                    <Stack direction={'horizontal'}>
                      <RemediationTimeTile {...cardProps} />
                    </Stack>
                  )}
                </Stack>
              </Stack.Item>
            )}

            <MostPrevalentRulesCard {...cardProps} />
          </Stack>

          <Stack direction={'horizontal'}>
            <Stack.Item grow>
              <RepositoriesTable {...cardProps} />
            </Stack.Item>
          </Stack>
        </Stack>
      </PageLayout.Content>
    </PageLayout>
  )
}
