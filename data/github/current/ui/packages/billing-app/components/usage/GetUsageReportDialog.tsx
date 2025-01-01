import {DownloadIcon, TriangleDownIcon} from '@primer/octicons-react'
import {
  ActionList,
  ActionMenu,
  Box,
  Button,
  ButtonGroup,
  Flash,
  FormControl,
  Link,
  Radio,
  RadioGroup,
  Text,
} from '@primer/react'
import {Banner, Dialog} from '@primer/react/experimental'
import {parseISO} from 'date-fns'
import type React from 'react'
import type {PropsWithChildren} from 'react'
import {Fragment, useEffect, useMemo, useRef, useState} from 'react'

import type {RangeSelection} from '@github-ui/date-picker'
import {DatePicker} from '@github-ui/date-picker'
import {isFeatureEnabled} from '@github-ui/feature-flags'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'

import {USAGE_REPORT_CUSTOM_RANGE, USAGE_REPORT_HOURLY_PERIOD, USAGE_REPORT_LEGACY_REPORT} from '../../constants'
import {doRequest, HTTPMethod} from '../../hooks/use-request'
import useRoute from '../../hooks/use-route'
import {USAGE_REPORT_ROUTE} from '../../routes'
import type {UsageReportRequest, UsageReportSelection} from '../../types/usage'
import {getDateString} from '../../utils'

const MAX_CUSTOM_RANGE_DAYS = 31
const TODAY = new Date()

interface Props {
  usageReportSelections: UsageReportSelection[]
  currentUserEmail: string
  disableUsageReports?: boolean
  vnextMigrationDate?: string
  minCustomDate: string
  copilotPremiumReportEnabled?: boolean
}

const ValidationErrorBanner = ({
  message,
  bannerRef,
}: {
  message: React.JSX.Element
  bannerRef?: React.RefObject<HTMLDivElement>
}) => (
  <Box sx={{mb: 3}} data-testid="error-validation-banner">
    <Banner ref={bannerRef} hideTitle variant="critical" title="Custom date range input is empty">
      <Banner.Description>{message}</Banner.Description>
    </Banner>
  </Box>
)

export default function GetUsageReportDialog({
  usageReportSelections,
  currentUserEmail,
  disableUsageReports = false,
  vnextMigrationDate,
  minCustomDate,
  copilotPremiumReportEnabled = false,
}: Props) {
  const {path: requestUsageReportRoute} = useRoute(USAGE_REPORT_ROUTE)
  const [usageReportPeriod, setUsageReportPeriod] = useState<number>(USAGE_REPORT_HOURLY_PERIOD)
  const [isDialogOpen, setIsDialogOpen] = useState(false)
  const [range, setRange] = useState<RangeSelection | null>(null)
  const returnFocusRef = useRef(null)
  const bannerRef = useRef<HTMLDivElement>(null)
  const {addToast} = useToastContext()
  const [showEmptyCustomDateRangeError, setEmptyCustomDateRangeError] = useState(false)

  const minCustomDateUTC = useMemo(() => {
    return parseISO(minCustomDate)
  }, [minCustomDate])

  const handleSubmit = async (e: React.FormEvent<EventTarget>) => {
    e.preventDefault()

    if (usageReportPeriod === USAGE_REPORT_CUSTOM_RANGE && !range) {
      setEmptyCustomDateRangeError(true)
      return
    }

    try {
      const requestData: UsageReportRequest = {
        period: usageReportPeriod,
      }

      if (usageReportPeriod === USAGE_REPORT_CUSTOM_RANGE && range?.from && range?.to) {
        const {startDate, endDate} = getDateString(range)
        requestData.start = startDate
        requestData.end = endDate
      }

      const {ok, data} = await doRequest<UsageReportRequest>(HTTPMethod.POST, requestUsageReportRoute, requestData)

      if (!ok) {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'error',
          message: data.error ?? 'There was an issue sending your usage report request',
          role: 'alert',
        })
      } else {
        // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
        addToast({
          type: 'success',
          message: `We're preparing your usage report. We'll send an email to ${currentUserEmail} when it's ready.`,
          role: 'status',
        })
      }
    } catch {
      // eslint-disable-next-line @github-ui/dotcom-primer/toast-migration
      addToast({
        type: 'error',
        message: 'There was an issue sending your usage report request',
        role: 'alert',
      })
    } finally {
      setIsDialogOpen(false)
    }
  }

  const handleRadioGroupChange = (
    selectedValue: string | null,
    _e?: React.ChangeEvent<HTMLInputElement> | undefined,
  ) => {
    setUsageReportPeriod(Number(selectedValue))

    if (selectedValue !== USAGE_REPORT_CUSTOM_RANGE.toString()) {
      setEmptyCustomDateRangeError(false)
    }
  }

  useEffect(() => {
    if (showEmptyCustomDateRangeError) {
      bannerRef.current?.focus()
    }
  }, [showEmptyCustomDateRangeError])

  return (
    <Box onSubmit={handleSubmit} sx={{pt: [2, 0]}} data-testid="usage-report-dialog-container">
      {isFeatureEnabled('copilot_overages_usage_report') && copilotPremiumReportEnabled ? (
        <ButtonGroup>
          <Button leadingVisual={<DownloadIcon />} onClick={() => setIsDialogOpen(true)}>
            Get usage report
          </Button>

          <ActionMenu>
            <ActionMenu.Button icon={TriangleDownIcon} aria-label="More options" />

            <ActionMenu.Overlay width="large">
              <ActionList showDividers>
                <ActionList.Item onSelect={() => setIsDialogOpen(true)}>
                  Metered billing usage report
                  <ActionList.Description variant="block">
                    Provides a breakdown of all metered usage
                  </ActionList.Description>
                </ActionList.Item>

                <ActionList.Item onSelect={() => {}}>
                  Copilot premium requests usage report
                  <ActionList.Description variant="block">
                    Provides a per user breakdown of requests exhausted and their monthly quota for the current billing
                    period
                  </ActionList.Description>
                </ActionList.Item>
              </ActionList>
            </ActionMenu.Overlay>
          </ActionMenu>
        </ButtonGroup>
      ) : (
        <Button leadingVisual={<DownloadIcon />} onClick={() => setIsDialogOpen(true)} sx={{width: ['100%', 'auto']}}>
          Get usage report
        </Button>
      )}

      {isDialogOpen && (
        <Dialog
          onClose={() => setIsDialogOpen(false)}
          title="Get usage report"
          subtitle={`The usage report will be emailed when it's ready to ${currentUserEmail}.`}
          returnFocusRef={returnFocusRef}
          aria-labelledby="header"
          sx={{overflowY: 'auto'}}
        >
          {disableUsageReports && (
            <Flash
              data-testid="disable-usage-report-banner"
              variant="warning"
              sx={{display: 'flex', alignItems: 'center'}}
            >
              <span>
                Usage reports are temporarily disabled due to planned maintenance. Please try again later or reach out
                to support for assistance.
              </span>
            </Flash>
          )}

          <form>
            {showEmptyCustomDateRangeError && (
              <ValidationErrorBanner
                bannerRef={bannerRef}
                message={
                  <>
                    Please specify a{' '}
                    <Link inline muted href="#">
                      custom date range
                    </Link>{' '}
                    to continue.
                  </>
                }
              />
            )}
            <div>
              <span id="radio-header">Select time frame:</span>

              <Box sx={{gap: 3, display: 'flex', flexDirection: 'column', pt: 2}}>
                <RadioGroup name="reportChoiceGroup" onChange={handleRadioGroupChange} aria-labelledby="radio-header">
                  {usageReportSelections.map(selection => {
                    const sharedProps = {
                      value: `${selection.type}`,
                      defaultChecked: selection.type === usageReportPeriod,
                      displayText: selection.displayText,
                    }

                    if (
                      selection.type === USAGE_REPORT_CUSTOM_RANGE &&
                      usageReportPeriod === USAGE_REPORT_CUSTOM_RANGE
                    ) {
                      return (
                        <DatePickerControl
                          key={selection.type}
                          legacySelection={false}
                          range={range}
                          setRange={setRange}
                          showEmptyCustomDateRangeError={showEmptyCustomDateRangeError}
                          setEmptyCustomDateRangeError={setEmptyCustomDateRangeError}
                          dateText={selection.dateText}
                          minCustomDate={minCustomDateUTC}
                          {...sharedProps}
                        />
                      )
                    }

                    return selection.type !== USAGE_REPORT_LEGACY_REPORT ? (
                      <ReportControl
                        {...sharedProps}
                        dateText={selection.dateText}
                        key={selection.type}
                        legacySelection={false}
                      />
                    ) : (
                      <Fragment key={selection.type}>
                        <Box as="hr" sx={{mt: 2, mb: 0}} />
                        <LegacyReportControl {...sharedProps} vnextMigrationDate={vnextMigrationDate} legacySelection />
                      </Fragment>
                    )
                  })}
                </RadioGroup>
              </Box>
              <hr />

              {usageReportPeriod !== USAGE_REPORT_LEGACY_REPORT && (
                <span>A detailed report will be generated of your metered usage, with all times reported in UTC.</span>
              )}

              <Box sx={{pt: 3, display: 'flex', alignItems: 'center', justifyContent: 'flex-end'}}>
                <Button sx={{mr: 2}} onClick={() => setIsDialogOpen(false)}>
                  Cancel
                </Button>
                <Button type="submit" variant="primary" onClick={handleSubmit} disabled={disableUsageReports}>
                  Email me the report
                </Button>
              </Box>
            </div>
          </form>
        </Dialog>
      )}
    </Box>
  )
}

type SharedProps = {
  value: string
  defaultChecked?: boolean
  displayText: string
  legacySelection: boolean
}

function MyControl({
  children,
  value,
  defaultChecked,
  displayText,
  legacySelection = false,
}: PropsWithChildren<SharedProps>) {
  return (
    <FormControl>
      <Radio
        value={value}
        defaultChecked={defaultChecked}
        data-testid={`report-control-id-${legacySelection ? 'legacy' : 'non-legacy'}`}
      />
      <FormControl.Label sx={{fontWeight: 'normal'}}>
        {displayText} <Text sx={{color: 'fg.muted', fontSize: 'small', ml: 2}}>{children}</Text>
      </FormControl.Label>
    </FormControl>
  )
}

function ReportControl({dateText, ...rest}: SharedProps & {dateText: string}) {
  return <MyControl {...rest}>{`${dateText}`}</MyControl>
}

function LegacyReportControl({vnextMigrationDate, ...rest}: SharedProps & {vnextMigrationDate?: string}) {
  return (
    <MyControl {...rest}>
      <>
        <br />
        Get a usage report for days before {vnextMigrationDate}, before your organization transitioned to the enhanced
        billing platform.
      </>
    </MyControl>
  )
}

function DatePickerControl({
  range,
  setRange,
  showEmptyCustomDateRangeError,
  setEmptyCustomDateRangeError,
  dateText,
  minCustomDate,
  ...rest
}: SharedProps & {
  range: RangeSelection | null
  setRange: React.Dispatch<React.SetStateAction<RangeSelection | null>>
  dateText: string
  showEmptyCustomDateRangeError?: boolean
  setEmptyCustomDateRangeError: React.Dispatch<React.SetStateAction<boolean>>
  minCustomDate: Date
}) {
  const handleDatePicker = (selection: RangeSelection | null) => {
    if (!selection) return
    setRange(selection)
    setEmptyCustomDateRangeError(false)
  }

  return (
    <MyControl {...rest} legacySelection={false}>
      {`${dateText}`}
      <Box sx={{mt: '6px'}}>
        <DatePicker
          variant="range"
          showTodayButton
          dateFormat="long"
          placeholder="Choose date..."
          maxDate={TODAY}
          maxRangeSize={MAX_CUSTOM_RANGE_DAYS}
          value={range}
          onChange={selection => handleDatePicker(selection)}
          confirmation
          minDate={minCustomDate}
          anchoredOverlayProps={{side: 'outside-top'}}
        />
      </Box>
      {showEmptyCustomDateRangeError && (
        <FormControl.Validation variant="error" sx={{mt: 1, fontSize: 'small', fontWeight: 'normal'}}>
          Specify a custom date range
        </FormControl.Validation>
      )}
    </MyControl>
  )
}
