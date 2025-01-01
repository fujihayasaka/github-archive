import type React from 'react'
import {useState, useRef, Fragment, useMemo, useEffect} from 'react'

import type {PropsWithChildren} from 'react'
import {Text, Box, Button, RadioGroup, Radio, FormControl, Flash, Link} from '@primer/react'
import {Banner, Dialog} from '@primer/react/experimental'
// eslint-disable-next-line no-restricted-imports
import {useToastContext} from '@github-ui/toast/ToastContext'
import {parseISO} from 'date-fns'

import {USAGE_REPORT_HOURLY_PERIOD, USAGE_REPORT_LEGACY_REPORT, USAGE_REPORT_CUSTOM_RANGE} from '../../constants'
import useRoute from '../../hooks/use-route'
import {doRequest, HTTPMethod} from '../../hooks/use-request'
import {USAGE_REPORT_ROUTE} from '../../routes'
import {DatePicker} from '@github-ui/date-picker'

import type {UsageReportSelection, UsageReportRequest} from '../../types/usage'
import type {RangeSelection} from '@github-ui/date-picker'

const MAX_CUSTOM_RANGE_DAYS = 31
const TODAY = new Date()

interface Props {
  usageReportSelections: UsageReportSelection[]
  currentUserEmail: string
  billingPlatformEnabledProducts: string[]
  disableUsageReports?: boolean
  vnextMigrationDate?: string
  showCustomDateRangeUsageReport: boolean
  minCustomDate: string
}

const ValidationErrorBanner = ({
  message,
  bannerRef,
}: {
  message: React.JSX.Element
  bannerRef?: React.RefObject<HTMLDivElement>
}) => (
  <Box sx={{px: 3, pt: 3}} data-testid="error-validation-banner">
    <Banner ref={bannerRef} hideTitle variant="critical" title="Custom date range input is empty">
      <Banner.Description>{message}</Banner.Description>
    </Banner>
  </Box>
)

export default function GetUsageReportDialog({
  usageReportSelections,
  currentUserEmail,
  billingPlatformEnabledProducts,
  disableUsageReports = false,
  vnextMigrationDate,
  showCustomDateRangeUsageReport,
  minCustomDate,
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

    if (showCustomDateRangeUsageReport && usageReportPeriod === USAGE_REPORT_CUSTOM_RANGE && !range) {
      setEmptyCustomDateRangeError(true)
      return
    }

    try {
      const requestData: UsageReportRequest = {
        period: usageReportPeriod,
      }

      if (
        showCustomDateRangeUsageReport &&
        usageReportPeriod === USAGE_REPORT_CUSTOM_RANGE &&
        range?.from &&
        range?.to
      ) {
        // Convert dates to ISO string format
        requestData.start = new Date(range.from).toISOString().split('T')[0]
        requestData.end = new Date(range.to).toISOString().split('T')[0]
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

    if (showCustomDateRangeUsageReport && selectedValue !== USAGE_REPORT_CUSTOM_RANGE.toString()) {
      setEmptyCustomDateRangeError(false)
    }
  }

  /* Builds the text to list the products that the usage report will contain */
  const enabledProductListText = (): string => {
    if (billingPlatformEnabledProducts.length <= 1) return billingPlatformEnabledProducts[0] ?? ''

    const lastTwoProducts = billingPlatformEnabledProducts.slice(-2)
    const remainingProducts = billingPlatformEnabledProducts.slice(0, -2)
    const lastTwoText = `${lastTwoProducts[0]} and ${lastTwoProducts[1]}`

    if (billingPlatformEnabledProducts.length > 2) {
      return `${remainingProducts.join(', ')}, ${lastTwoText}`
    } else {
      return lastTwoText
    }
  }

  useEffect(() => {
    if (showCustomDateRangeUsageReport && showEmptyCustomDateRangeError) {
      bannerRef.current?.focus()
    }
  }, [showCustomDateRangeUsageReport, showEmptyCustomDateRangeError])

  return (
    <Box onSubmit={handleSubmit} sx={{pt: [2, 0]}} data-testid="usage-report-dialog-container">
      <Button onClick={() => setIsDialogOpen(true)} sx={{width: ['100%', 'auto']}}>
        Get usage report
      </Button>
      {isDialogOpen && (
        <Dialog
          onClose={() => setIsDialogOpen(false)}
          title="Get usage report"
          subtitle={
            showCustomDateRangeUsageReport
              ? `The usage report will be emailed when it's ready to ${currentUserEmail}.`
              : ''
          }
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
            {showCustomDateRangeUsageReport && showEmptyCustomDateRangeError && (
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
            <Box sx={{px: 3, pt: 3}}>
              <span id="radio-header">
                {showCustomDateRangeUsageReport ? 'Select time frame:' : 'Select time period:'}
              </span>

              <Box sx={{gap: 3, display: 'flex', flexDirection: 'column', pt: 3}}>
                <RadioGroup name="reportChoiceGroup" onChange={handleRadioGroupChange} aria-labelledby="radio-header">
                  {usageReportSelections.map(selection => {
                    const sharedProps = {
                      value: `${selection.type}`,
                      defaultChecked: selection.type === usageReportPeriod,
                      displayText: selection.displayText,
                    }

                    if (
                      showCustomDateRangeUsageReport &&
                      selection.type === USAGE_REPORT_CUSTOM_RANGE &&
                      usageReportPeriod === USAGE_REPORT_CUSTOM_RANGE
                    ) {
                      return (
                        <DatePickerControl
                          key={selection.type}
                          legacySelection={false}
                          range={range}
                          setRange={setRange}
                          showCustomDateRangeUsageReport
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
                        showCustomDateRangeUsageReport={showCustomDateRangeUsageReport}
                      />
                    ) : (
                      <Fragment key={selection.type}>
                        <Box as="hr" sx={{margin: 0}} />
                        <LegacyReportControl
                          {...sharedProps}
                          vnextMigrationDate={vnextMigrationDate}
                          legacySelection
                          showCustomDateRangeUsageReport={showCustomDateRangeUsageReport}
                        />
                      </Fragment>
                    )
                  })}
                </RadioGroup>
              </Box>
              {!(showCustomDateRangeUsageReport && usageReportPeriod === USAGE_REPORT_LEGACY_REPORT) && <hr />}

              {!showCustomDateRangeUsageReport && usageReportPeriod !== USAGE_REPORT_LEGACY_REPORT && (
                <span>
                  A detailed report will be generated including usage for{' '}
                  <Text sx={{fontWeight: 'bold'}} data-testid="usage-report-enabled-products-text">
                    {enabledProductListText()}
                  </Text>
                  .
                </span>
              )}

              {!showCustomDateRangeUsageReport && (
                <Box sx={{pt: 2}}>
                  <span>
                    We will email you at <Text sx={{fontWeight: 'bold'}}>{currentUserEmail}</Text> once the report is
                    ready for download.
                  </span>
                </Box>
              )}

              {!showCustomDateRangeUsageReport && usageReportPeriod !== USAGE_REPORT_LEGACY_REPORT && (
                <>
                  <Box sx={{pt: 2}}>
                    <span>
                      Please note that updates to organization name, repository name, and username fields may take up to
                      24 hours. For the most current report, request your usage report again after this period.
                    </span>
                  </Box>
                </>
              )}

              {showCustomDateRangeUsageReport && usageReportPeriod !== USAGE_REPORT_LEGACY_REPORT && (
                <span>A detailed report will be generated including your metered usage.</span>
              )}

              {showCustomDateRangeUsageReport ? (
                <Box sx={{py: 3, display: 'flex', alignItems: 'center', justifyContent: 'flex-end'}}>
                  <Button sx={{mr: 2}} onClick={() => setIsDialogOpen(false)}>
                    Cancel
                  </Button>
                  <Button type="submit" variant="primary" onClick={handleSubmit} disabled={disableUsageReports}>
                    Email me the report
                  </Button>
                </Box>
              ) : (
                <Box sx={{py: 3}}>
                  <Button
                    type="submit"
                    variant="primary"
                    sx={{width: '100%'}}
                    onClick={handleSubmit}
                    disabled={disableUsageReports}
                  >
                    Email usage report
                  </Button>
                </Box>
              )}
            </Box>
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
  showCustomDateRangeUsageReport: boolean
}

function MyControl({
  children,
  value,
  defaultChecked,
  displayText,
  legacySelection = false,
  showCustomDateRangeUsageReport,
}: PropsWithChildren<SharedProps>) {
  return (
    <FormControl>
      <Radio
        value={value}
        defaultChecked={defaultChecked}
        data-testid={`report-control-id-${legacySelection ? 'legacy' : 'non-legacy'}`}
      />
      <FormControl.Label sx={{fontWeight: 'normal'}}>
        {displayText}{' '}
        <Text sx={{color: 'fg.muted', fontSize: 'small', ...(showCustomDateRangeUsageReport && {ml: 2})}}>
          {children}
        </Text>
      </FormControl.Label>
    </FormControl>
  )
}

function ReportControl({dateText, showCustomDateRangeUsageReport, ...rest}: SharedProps & {dateText: string}) {
  return (
    <MyControl {...rest} showCustomDateRangeUsageReport={showCustomDateRangeUsageReport}>
      {showCustomDateRangeUsageReport ? `${dateText}` : `(${dateText})`}
    </MyControl>
  )
}

function LegacyReportControl({
  vnextMigrationDate,
  showCustomDateRangeUsageReport,
  ...rest
}: SharedProps & {vnextMigrationDate?: string}) {
  return (
    <MyControl {...rest} showCustomDateRangeUsageReport={showCustomDateRangeUsageReport}>
      {showCustomDateRangeUsageReport ? (
        <>
          <br />
          Get a usage report for days before {vnextMigrationDate}, before your organization transitioned to the enhanced
          billing platform.
        </>
      ) : (
        <>
          <br />
          Your enterprise account has transitioned to the enhanced billing platform on {vnextMigrationDate}. Selecting
          this option will generate a usage report for all available days prior to {vnextMigrationDate}.
        </>
      )}
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
      <Box sx={{mt: 1}}>
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
