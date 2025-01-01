import {testIdProps} from '@github-ui/test-id-props'
import {PencilIcon} from '@primer/octicons-react'
import {Button, Heading} from '@primer/react'
import {memo, useCallback, useRef} from 'react'
import {useParams} from 'react-router-dom'

import {ErrorBoundary} from '../../../components/error-boundaries/error-boundary'
import {ViewerPrivileges} from '../../../helpers/viewer-privileges'
import {useEnabledFeatures} from '../../../hooks/use-enabled-features'
import {useLoadRequiredFieldsForChartConfiguration} from '../../../hooks/use-load-required-fields'
import {FILTER_QUERY_PARAM} from '../../../platform/url'
import {useChartTotalCount} from '../../../queries/use-chart-total-count'
import {useSearchParams} from '../../../router'
import {getDirtyChartState, isDefaultChart, isHistoricalChart} from '../../../state-providers/charts/chart-helpers'
import {useChartActions} from '../../../state-providers/charts/use-chart-actions'
import {type ChartState, useCharts} from '../../../state-providers/charts/use-charts'
import {useInsightsConfigurationPane} from '../hooks/use-insights-configuration-pane'
import {useInsightsFilters} from '../hooks/use-insights-filters'
import {useInsightsTime} from '../hooks/use-insights-time'
import {CurrentInsightsChart} from './current-insights-chart'
import {ChartErrorFallback} from './error-messages/chart-error-fallback'
import {InvalidConfigError} from './error-messages/invalid-config-error'
import {MissingChartError} from './error-messages/missing-chart-error'
import {InsightsChartName} from './insights-chart-name'
import styles from './insights-chart-view.module.css'
import {InsightsConfigurationPane} from './insights-configuration-pane/insights-configuration-pane'
import {InsightsFilters} from './insights-filters'
import {LeanHistoricalInsightsChart} from './lean-historical-insights-chart'
import {InsightCustomDatePicker} from './period-navigation/insight-custom-date-picker'
import {PeriodNavigation} from './period-navigation/period-navigation'

export const InsightsChartView = memo(function InsightChartView() {
  const params = useParams()

  const {getChartConfigurationByNumber} = useCharts()
  const chart = getChartConfigurationByNumber(params.insightNumber ? Number(params.insightNumber) : 0)

  if (!chart) {
    return <MissingChartError />
  }

  const errorFallback = <ChartErrorFallback />

  return (
    <ErrorBoundary key={chart.number} fallback={errorFallback}>
      <InsightChartContent chart={chart} />
    </ErrorBoundary>
  )
})

const InsightChartContent = memo<{chart: ChartState}>(function InsightChartContent({chart}) {
  const {hasWritePermissions} = ViewerPrivileges()
  const {updateChartConfiguration} = useChartActions()
  const [searchParams, setSearchParams] = useSearchParams()
  const {
    filteredItems,
    filterValue,
    handleFilterValueChange,
    handleNewFilterBarValueChange,
    onClearButtonClick,
    setValueFromSuggestion,
    resetFilter,
    inputRef,
  } = useInsightsFilters(chart)
  const {endDate, period, startDate} = useInsightsTime(chart)
  const {openPane, isOpen} = useInsightsConfigurationPane()
  const {memex_table_without_limits} = useEnabledFeatures()

  const {filterCount} = memex_table_without_limits
    ? // eslint-disable-next-line react-hooks/react-compiler
      // eslint-disable-next-line react-hooks/rules-of-hooks
      useChartTotalCount(chart.localVersion.configuration)
    : {filterCount: filteredItems?.length}

  const {isValid} = useLoadRequiredFieldsForChartConfiguration(chart.localVersion.configuration)

  const handleSaveChanges = useCallback(async () => {
    if (isDefaultChart(chart)) return
    await updateChartConfiguration.perform({
      chartNumber: chart.number,
      chart: {
        configuration: {
          ...chart.localVersion.configuration,
          filter: filterValue,
        },
      },
    })
    const nextParams = new URLSearchParams(searchParams)
    nextParams.delete(FILTER_QUERY_PARAM)
    setSearchParams(nextParams, {replace: true})
  }, [chart, filterValue, searchParams, setSearchParams, updateChartConfiguration])

  const dirtyState = getDirtyChartState(chart)

  const chartIsDefault = isDefaultChart(chart)
  const isUserDefinedChart = !chartIsDefault
  const isHistorical = isHistoricalChart(chart)

  const configureButtonRef = useRef<HTMLButtonElement | null>(null)

  return (
    <div className={styles.HeadingContainer}>
      <Heading {...testIdProps('insights-header')} as="h2" className={styles.Heading}>
        {chartIsDefault ? chart.name : <InsightsChartName chart={chart} />}
        {hasWritePermissions && (
          <div>
            <Button
              ref={configureButtonRef}
              leadingVisual={PencilIcon}
              onClick={openPane}
              {...testIdProps('insights-configuration-pane-button-open')}
            >
              Configure
            </Button>
          </div>
        )}
      </Heading>
      {chart.description ? (
        <span className={styles.Description} {...testIdProps('insights-description')}>
          {chart.description}{' '}
        </span>
      ) : null}
      <div className={styles.FiltersContainer}>
        <div className={styles.Filters}>
          <InsightsFilters
            inputRef={inputRef}
            filterValue={filterValue}
            filterCount={filterCount}
            handleFilterValueChange={handleFilterValueChange}
            handleNewFilterBarValueChange={handleNewFilterBarValueChange}
            onClearButtonClick={onClearButtonClick}
            setValueFromSuggestion={setValueFromSuggestion}
            onSaveChanges={isUserDefinedChart && dirtyState.isFilterDirty ? handleSaveChanges : undefined}
            hideSaveButton={!isUserDefinedChart || !hasWritePermissions}
            onResetChanges={dirtyState.isFilterDirty ? resetFilter : undefined}
          />
        </div>
      </div>
      {!isValid ? (
        <InvalidConfigError />
      ) : (
        <>
          {isHistorical ? (
            <div className={styles.DatePickerContainer}>
              <PeriodNavigation period={period} />
              <InsightCustomDatePicker startDate={startDate} endDate={endDate} />
            </div>
          ) : null}
          <div className={styles.ChartContainer}>
            <div className={styles.ChartBuffer}>
              {isHistorical ? (
                <LeanHistoricalInsightsChart
                  configuration={chart.localVersion.configuration}
                  filteredItems={filteredItems}
                  filterValue={filterValue}
                  startDate={startDate}
                  endDate={endDate}
                />
              ) : (
                <CurrentInsightsChart
                  configuration={chart.localVersion.configuration}
                  filterValue={filterValue}
                  filteredItems={filteredItems}
                />
              )}
            </div>
          </div>
        </>
      )}
      {isOpen && <InsightsConfigurationPane chart={chart} returnFocusRef={configureButtonRef} />}
    </div>
  )
})
