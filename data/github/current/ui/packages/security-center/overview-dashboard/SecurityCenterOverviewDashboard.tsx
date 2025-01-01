import type {RangeSelection} from '@github-ui/date-picker'
import type {FilterProvider} from '@github-ui/filter'
import {updateUrl} from '@github-ui/history'
import {OnboardingTipBanner} from '@github-ui/onboarding-tip-banner'
import {SingleSignOnBanner} from '@github-ui/single-sign-on-banner'
import {useSso} from '@github-ui/use-sso'
import {InfoIcon, ShieldCheckIcon} from '@primer/octicons-react'
import {clsx} from 'clsx'
import {useCallback, useEffect, useMemo, useState} from 'react'
import {useSearchParams} from 'react-router-dom'

import {dateSpansAreEqual, isRangeSelection} from '../common/components/date-span-picker'
import {ExportBanner} from '../common/components/export-banner'
import PageLayout from '../common/components/page-layout'
import {usePaths} from '../common/contexts/Paths'
import type {CustomProperty} from '../common/filter-providers/types'
import {useDirtyStateTracking} from '../common/hooks/use-dirty-state-tracking'
import {toUTCDateString} from '../common/utils/date-formatter'
import {calculateDateRangeFromPeriod, type Period} from '../common/utils/date-period'
import type {GroupingType} from './components/alert-trends-chart/grouping-type'
import {DetectionView} from './components/DetectionView'
import {PreventionView} from './components/PreventionView'
import {RemediationView} from './components/RemediationView'
import {useUpdateUrl} from './hooks/use-update-url'
import styles from './SecurityCenterOverviewDashboard.module.css'

type ImpactAnalysisTab = 'repositories' | 'advisories' | 'sast'

type IncompleteDataWarning = {show: true; docHref: string} | {show: false}
export interface SecurityCenterOverviewDashboardProps {
  initialQuery?: string
  initialDateSpan?: Period | {from: string; to: string}
  initialSelectedImpactAnalysisTable?: ImpactAnalysisTab
  feedbackLink: {
    text: string
    url: string
  }
  visibleSecurityFeatures: string[]
  alertTrendsChart?: {
    grouping?: GroupingType
  }
  incompleteDataWarning?: IncompleteDataWarning
  customProperties: CustomProperty[]
  filterProviders: FilterProvider[]
  showOnboardingBanner?: boolean
  exportErrorMessage?: string
  scope?: string
  showCsvExport: boolean
  allowAutofixFeatures?: boolean
  allowOwnerTypeFiltering?: boolean
}

// the RangeSelection passed by params uses strings; convert to Dates
function ensureDateRangeUsesDates(
  dateSpan: Period | RangeSelection | {from: string; to: string},
): Period | RangeSelection {
  if ('period' in dateSpan) {
    return dateSpan
  } else {
    return {
      from: new Date(dateSpan.from),
      to: new Date(dateSpan.to),
    }
  }
}

const DEFAULT_DATE_SPAN: Period = {period: 'last30days'}
const DEFAULT_VIEW: View = 'detection'

type View = 'detection' | 'remediation' | 'prevention'
type ViewDatasetMap = {
  [key in View]: {
    label: string
  }
}

const viewMap: ViewDatasetMap = {
  detection: {
    label: 'Detection',
  },
  remediation: {
    label: 'Remediation',
  },
  prevention: {
    label: 'Prevention',
  },
}

function isView(value: string | null): value is View {
  // You can't interrogate a constrained type, and we shouldn't repeat the values here.
  // The view map uses the view values as keys, so we know this is safe.
  return value != null && Object.keys(viewMap).includes(value)
}

export function SecurityCenterOverviewDashboard({
  alertTrendsChart,
  feedbackLink,
  initialDateSpan,
  initialQuery,
  initialSelectedImpactAnalysisTable = 'repositories',
  // eslint-disable-next-line @eslint-react/no-unstable-default-props
  incompleteDataWarning = {show: false},
  customProperties,
  filterProviders,
  showOnboardingBanner,
  exportErrorMessage,
  scope,
  showCsvExport,
  allowAutofixFeatures,
}: SecurityCenterOverviewDashboardProps): JSX.Element {
  const [initialParams] = useSearchParams()

  // track selected nav state
  const initialView = initialParams.get('view')
  const [view, setView] = useState<View>(() => (isView(initialView) ? initialView : DEFAULT_VIEW))
  const [viewIsDirty] = useDirtyStateTracking(view, DEFAULT_VIEW, !!initialView)

  const {ssoOrgs} = useSso()
  const ssoOrgNames = ssoOrgs.map(o => o['login']).filter(n => n !== undefined)

  const defaultQuery = 'archived:false tool:github'

  // track selected filter state
  const [submittedQuery, setSubmittedQuery] = useState(initialQuery ?? defaultQuery)
  const [submittedQueryIsDirty, resetSubmittedQueryIsDirty] = useDirtyStateTracking(
    submittedQuery,
    defaultQuery,
    !!initialQuery,
  )

  // track selected date span state
  const [selectedDateSpan, setSelectedDateSpan] = useState(() =>
    initialDateSpan != null ? ensureDateRangeUsesDates(initialDateSpan) : DEFAULT_DATE_SPAN,
  )
  const [dateSpanIsDirty, resetDateSpanIsDirty] = useDirtyStateTracking(
    selectedDateSpan,
    DEFAULT_DATE_SPAN,
    !!initialDateSpan,
    dateSpansAreEqual,
  )

  const dateRange = useMemo(() => {
    if (isRangeSelection(selectedDateSpan)) {
      return selectedDateSpan
    } else {
      return calculateDateRangeFromPeriod(selectedDateSpan)
    }
  }, [selectedDateSpan])
  const startDateString = useMemo(() => toUTCDateString(dateRange.from), [dateRange])
  const endDateString = useMemo(() => toUTCDateString(dateRange.to), [dateRange])

  const onRevert = (): void => {
    setSubmittedQuery(defaultQuery)
    resetSubmittedQueryIsDirty()
    setSelectedDateSpan(DEFAULT_DATE_SPAN)
    resetDateSpanIsDirty()
  }

  // keep browser URL in sync with selected filter and date span
  useUpdateUrl(
    submittedQuery,
    submittedQueryIsDirty,
    dateSpanIsDirty,
    startDateString,
    endDateString,
    '', // selected table is handled in the DetectionView
    selectedDateSpan,
    view,
    viewIsDirty,
  )

  // Don't preserve the ImpactAnalysisTab when switching views
  useEffect(() => {
    if (view !== 'detection') {
      const url = new URL(window.location.href, window.location.origin)
      const nextParams = url.searchParams

      nextParams.delete('impactAnalysisTab')
      updateUrl(`${url.pathname}${url.search}`)
    }
  }, [view])

  const dateSpanPickerCallback = useCallback((selection: RangeSelection | Period) => {
    if (isRangeSelection(selection) && selection.from === selection.to) {
      setSelectedDateSpan(DEFAULT_DATE_SPAN)
    } else {
      setSelectedDateSpan(selection)
    }
  }, [])

  const startedBannerId = 'security-center-export-started-banner'
  const successBannerId = 'security-center-export-success-banner'
  const errorBannerId = 'security-center-export-error-banner'

  const renderBannerWrapper = ssoOrgNames.length > 0 || showOnboardingBanner || showCsvExport

  // eslint-disable-next-line ssr-friendly/no-dom-globals-in-react-fc
  window.performance.mark('security_overview_dashboard_loaded')
  const paths = usePaths()
  return (
    <PageLayout>
      {renderBannerWrapper && (
        <PageLayout.Banners>
          {ssoOrgNames.length > 0 && <SingleSignOnBanner protectedOrgs={ssoOrgNames} />}
          {showOnboardingBanner && (
            <OnboardingTipBanner
              link={paths.onboardingAdvancedSecurityPath()}
              icon={ShieldCheckIcon}
              linkText="Back to onboarding"
              heading="View your security risk in a security overview"
            >
              {`Uncover insights to help prioritize efforts in your AppSec program and share progress with the various stakeholders across your ${scope} with detailed reporting in a security overview.`}
            </OnboardingTipBanner>
          )}
          {showCsvExport && <ExportBanner id={startedBannerId} type="accent" />}
          {showCsvExport && <ExportBanner id={successBannerId} type="success" />}
          {showCsvExport && <ExportBanner id={errorBannerId} type="danger" errorMessage={exportErrorMessage} />}
        </PageLayout.Banners>
      )}
      <PageLayout.Header
        title="Overview"
        description={`Alert trends and insights across your ${scope}.`}
        feedbackLink={feedbackLink}
      />
      <PageLayout.ExportButton
        exportUrl={
          showCsvExport
            ? paths.csvExportPath({startDate: startDateString, endDate: endDateString, query: submittedQuery})
            : undefined
        }
        startedBannerId={startedBannerId}
        successBannerId={successBannerId}
        errorBannerId={errorBannerId}
      />
      <PageLayout.FilterBar
        filter={<PageLayout.Filter providers={filterProviders} query={submittedQuery} onSubmit={setSubmittedQuery} />}
        datePicker={<PageLayout.DatePicker value={selectedDateSpan} onChange={dateSpanPickerCallback} />}
        revert={<PageLayout.FilterRevert show={submittedQueryIsDirty || dateSpanIsDirty} onRevert={onRevert} />}
      />
      <PageLayout.LimitedRepoWarning
        show={incompleteDataWarning.show}
        href={incompleteDataWarning.show ? incompleteDataWarning.docHref : ''}
      />
      <PageLayout.Nav
        onSelectionChanged={key => setView(key as View)}
        items={Object.keys(viewMap).map(key => {
          return {
            key,
            label: viewMap[key as View].label,
            selected: view === key,
          }
        })}
      />
      <PageLayout.Content>
        {view === 'detection' && (
          <DetectionView
            submittedQuery={submittedQuery}
            startDateString={startDateString}
            endDateString={endDateString}
            selectedDateSpan={selectedDateSpan}
            customProperties={customProperties}
            alertTrendsGrouping={alertTrendsChart?.grouping}
            initialSelectedImpactAnalysisTable={initialSelectedImpactAnalysisTable}
          />
        )}
        {view === 'remediation' && (
          <RemediationView
            submittedQuery={submittedQuery}
            startDateString={startDateString}
            endDateString={endDateString}
            alertTrendsGrouping={alertTrendsChart?.grouping}
            allowAutofixFeatures={allowAutofixFeatures}
          />
        )}
        {view === 'prevention' && (
          <PreventionView
            submittedQuery={submittedQuery}
            startDateString={startDateString}
            endDateString={endDateString}
            selectedDateSpan={selectedDateSpan}
            customProperties={customProperties}
            allowAutofixFeatures={allowAutofixFeatures}
          />
        )}
      </PageLayout.Content>
      <PageLayout.Footer>
        <p className={clsx('color-fg-muted', styles.Text)}>
          <InfoIcon /> All data is in UTC (GMT) time.
        </p>
      </PageLayout.Footer>
    </PageLayout>
  )
}
