import {ActionList, ActionMenu, Dialog} from '@primer/react'
import {Observer} from '../observables/Observer'
import type {IMetricsService} from '../services/metrics-service'
import {DateRangeType, GET_DATE_RANGE_LABEL} from '../models/enums'
import type {MetricsView} from '../models/models'
import {Services} from '../services/services'
import type {IAnalyticsService} from '../services/analytics-service'
import {LABELS} from '../resources/labels'
import {ObservableValue} from '../observables/observable'
import {DatePicker, type RangeSelection} from '@github-ui/date-picker'
import {Utils} from '../utils/utils'

const MAX_DATE_RANGE = 100
const OLDEST_VIEW_DAYS = 400

export interface MetricsDateRangeSelectorProps {
  metricsService: IMetricsService
}

export const MetricsDateRangeSelector = (props: MetricsDateRangeSelectorProps) => {
  const analyticsService = Services.get<IAnalyticsService>('IAnalyticsService')
  const metricsService = props.metricsService
  const state = metricsService.getMetricsView()
  const isDatePickerPanelOpen = new ObservableValue<boolean>(false)

  const viewCustomDateRange = state.value.customDateRange
  let datePickerValue: RangeSelection | null = null

  if (viewCustomDateRange?.end && viewCustomDateRange?.start) {
    datePickerValue = {
      from: Utils.fromUtc(new Date(viewCustomDateRange.start)),
      to: Utils.fromUtc(new Date(viewCustomDateRange.end)),
    }
  }

  const dateRange = new ObservableValue<RangeSelection | null>(datePickerValue)

  const dateRangeOptions: DateRangeOption[] = [
    GET_DATE_RANGE_OPTION(DateRangeType.CurrentWeek),
    GET_DATE_RANGE_OPTION(DateRangeType.CurrentMonth),
    GET_DATE_RANGE_OPTION(DateRangeType.LastMonth),
    GET_DATE_RANGE_OPTION(DateRangeType.Last30Days),
    GET_DATE_RANGE_OPTION(DateRangeType.Last90Days),
    GET_DATE_RANGE_OPTION(DateRangeType.LastYear),
    GET_DATE_RANGE_OPTION(DateRangeType.Custom),
  ]

  return (
    <Observer state={state} isDatePickerPanelOpen={isDatePickerPanelOpen} dateRange={dateRange}>
      {(obs: {state: MetricsView; isDatePickerPanelOpen: boolean; dateRange: RangeSelection | null}) => {
        const selectedOptionIndex = dateRangeOptions.findIndex(
          (option: DateRangeOption) => option.key === obs.state.dateRangeType,
        )
        const selectedOption = dateRangeOptions[selectedOptionIndex]
        let label = `${LABELS.period}: ${selectedOption?.display}`

        if (
          obs.state.dateRangeType === DateRangeType.Custom &&
          obs.state.customDateRange?.end &&
          obs.state.customDateRange?.start
        ) {
          const startDate = Utils.getUTCDateString(new Date(obs.state.customDateRange.start))
          const endDate = Utils.getUTCDateString(new Date(obs.state.customDateRange.end))
          label = `${startDate} - ${endDate}`
        }

        return (
          <>
            {obs.isDatePickerPanelOpen && (
              <Dialog
                title={LABELS.customDateRange}
                position="right"
                width="medium"
                onClose={() => {
                  isDatePickerPanelOpen.value = false
                }}
                footerButtons={[
                  {
                    buttonType: 'default',
                    content: LABELS.cancel,
                    onClick: () => {
                      isDatePickerPanelOpen.value = false
                    },
                  },
                  {
                    buttonType: 'primary',
                    content: LABELS.apply,
                    onClick: () => {
                      if (obs.dateRange && obs.dateRange.from && obs.dateRange.to)
                        metricsService.setDateRange(DateRangeType.Custom, {
                          start: Utils.toUtc(obs.dateRange.from).getTime(),
                          end: Utils.toUtc(obs.dateRange.to).getTime(),
                        })
                      isDatePickerPanelOpen.value = false
                    },
                  },
                ]}
              >
                <div className="d-flex flex-column gap-2">
                  <DatePicker
                    variant="range"
                    showTodayButton={false}
                    dateFormat="long"
                    maxDate={new Date()}
                    minDate={Utils.daysAgo(OLDEST_VIEW_DAYS)}
                    maxRangeSize={MAX_DATE_RANGE} // max of 100 days selectable for performance reasons
                    onChange={selection => {
                      if (selection) {
                        dateRange.value = selection
                      }
                    }}
                    value={datePickerValue}
                    placeholder={LABELS.chooseDates}
                  />
                </div>
              </Dialog>
            )}
            <ActionMenu>
              <ActionMenu.Button>
                <span className="f5">{label}</span>
              </ActionMenu.Button>
              <ActionMenu.Overlay width="medium">
                <ActionList selectionVariant="single">
                  {dateRangeOptions.map((option, index) => (
                    <ActionList.Item
                      // eslint-disable-next-line @eslint-react/no-array-index-key
                      key={index}
                      selected={index === selectedOptionIndex}
                      onSelect={() => {
                        analyticsService.logEvent('date-range-selector.select', 'MetricsDateRangeSelector', {
                          date: option.key,
                          previous: JSON.stringify(obs.state),
                        })
                        if (option.key !== DateRangeType.Custom) {
                          metricsService.setDateRange(option.key)
                        } else {
                          // eslint-disable-next-line react-hooks/react-compiler
                          isDatePickerPanelOpen.value = true
                        }
                      }}
                    >
                      {option.display}
                    </ActionList.Item>
                  ))}
                </ActionList>
              </ActionMenu.Overlay>
            </ActionMenu>
          </>
        )
      }}
    </Observer>
  )
}

interface DateRangeOption {
  key: DateRangeType
  display: string
}

const GET_DATE_RANGE_OPTION = (dateRange: DateRangeType): DateRangeOption => {
  return {display: GET_DATE_RANGE_LABEL(dateRange), key: dateRange}
}
