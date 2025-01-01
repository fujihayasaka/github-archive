import {render} from '@github-ui/react-core/test-utils'
import {act, screen} from '@testing-library/react'

import {GetUsageReportDialog} from '../../../components/usage'

import {
  USAGE_REPORT_SELECTIONS,
  USAGE_REPORT_SELECTIONS_WITH_LEGACY,
  USAGE_REPORT_CUSTOM_RANGE_SELECTIONS,
} from '../../../test-utils/mock-data'

describe('GetUsageReportDialog', () => {
  test('Opens dialog when usage report button clicked', async () => {
    render(
      <GetUsageReportDialog
        currentUserEmail="test@github.com"
        usageReportSelections={USAGE_REPORT_SELECTIONS}
        billingPlatformEnabledProducts={['Actions']}
        showCustomDateRangeUsageReport={false}
        minCustomDate="2024-11-11"
      />,
    )

    await expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    act(() => {
      screen.getByText('Get usage report').click()
    })
    await expect(screen.getByRole('dialog')).toBeVisible()
    expect(screen.queryByText('Custom range')).not.toBeInTheDocument()
  })

  describe('enabled products display text', () => {
    test('Renders enabled products text when one product enabled', async () => {
      render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          billingPlatformEnabledProducts={['Actions']}
          showCustomDateRangeUsageReport={false}
          minCustomDate="2024-11-11"
        />,
      )

      await expect(screen.queryByTestId('usage-report-dialog-header')).not.toBeInTheDocument()
      act(() => {
        screen.getByText('Get usage report').click()
      })
      await expect(screen.getByTestId('usage-report-enabled-products-text')).toHaveTextContent('Actions')
    })

    test('Renders enabled products text when two products enabled', async () => {
      render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          billingPlatformEnabledProducts={['Actions', 'Copilot']}
          showCustomDateRangeUsageReport={false}
          minCustomDate="2024-11-11"
        />,
      )

      await expect(screen.queryByTestId('usage-report-dialog-header')).not.toBeInTheDocument()
      act(() => {
        screen.getByText('Get usage report').click()
      })
      await expect(screen.getByTestId('usage-report-enabled-products-text')).toHaveTextContent('Actions and Copilot')
    })

    test('Renders enabled products text when three products enabled', async () => {
      render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          billingPlatformEnabledProducts={['Actions', 'Copilot', 'Ghec']}
          showCustomDateRangeUsageReport={false}
          minCustomDate="2024-11-11"
        />,
      )

      await expect(screen.queryByTestId('usage-report-dialog-header')).not.toBeInTheDocument()
      act(() => {
        screen.getByText('Get usage report').click()
      })
      await expect(screen.getByTestId('usage-report-enabled-products-text')).toHaveTextContent(
        'Actions, Copilot and Ghec',
      )
    })

    test('Renders enabled products text when four products enabled', async () => {
      render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          billingPlatformEnabledProducts={['Actions', 'Copilot', 'Enterprise', 'Advanced security']}
          showCustomDateRangeUsageReport={false}
          minCustomDate="2024-11-11"
        />,
      )

      await expect(screen.queryByTestId('usage-report-dialog-header')).not.toBeInTheDocument()
      act(() => {
        screen.getByText('Get usage report').click()
      })
      await expect(screen.getByTestId('usage-report-enabled-products-text')).toHaveTextContent(
        'Actions, Copilot, Enterprise and Advanced security',
      )
    })
  })

  test('usage report copy', async () => {
    render(
      <GetUsageReportDialog
        currentUserEmail="test@github.com"
        usageReportSelections={USAGE_REPORT_SELECTIONS}
        billingPlatformEnabledProducts={['Actions']}
        showCustomDateRangeUsageReport={false}
        minCustomDate="2024-11-11"
      />,
    )

    await expect(screen.queryByTestId('usage-report-dialog-header')).not.toBeInTheDocument()
    act(() => {
      screen.getByText('Get usage report').click()
    })

    expect(
      screen.getByText(
        /Please note that updates to organization name, repository name, and username fields may take up to 24 hours/,
      ),
    ).toBeInTheDocument()
  })

  describe('legacy report option', () => {
    test('legacy report option visible when its a selection', async () => {
      const {user} = render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS_WITH_LEGACY}
          billingPlatformEnabledProducts={['Actions']}
          showCustomDateRangeUsageReport={false}
          minCustomDate="2024-11-11"
        />,
      )

      await user.click(screen.getByText('Get usage report'))
      expect(screen.getByTestId('report-control-id-legacy')).toBeInTheDocument()

      expect(
        screen.getByText(/Your enterprise account has transitioned to the enhanced billing platform on/),
      ).toBeInTheDocument()
    })

    test('hide vnext text when legacy report is clicked', async () => {
      const {user} = render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS_WITH_LEGACY}
          billingPlatformEnabledProducts={['Actions']}
          vnextMigrationDate="Aug 1, 2022"
          showCustomDateRangeUsageReport={false}
          minCustomDate="2024-11-11"
        />,
      )

      await user.click(screen.getByText('Get usage report'))
      await user.click(screen.getByText('Legacy usage'))

      expect(screen.queryByText(/A detailed report will be generated including usage for /)).not.toBeInTheDocument()
      expect(screen.queryByText(/Please note that updates to organization name /)).not.toBeInTheDocument()
    })
  })

  describe('disabled usage reports', () => {
    test('Renders alert banner when usage reports are disabled', async () => {
      render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          billingPlatformEnabledProducts={['Actions']}
          disableUsageReports
          showCustomDateRangeUsageReport={false}
          minCustomDate="2024-11-11"
        />,
      )

      await expect(screen.queryByTestId('disable-usage-report-banner')).not.toBeInTheDocument()
      act(() => {
        screen.getByText('Get usage report').click()
      })
      await expect(screen.getByTestId('disable-usage-report-banner')).toBeInTheDocument()
    })

    test('Disable button when usage reports are disabled', async () => {
      render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          billingPlatformEnabledProducts={['Actions']}
          disableUsageReports
          showCustomDateRangeUsageReport={false}
          minCustomDate="2024-11-11"
        />,
      )

      await expect(screen.queryByTestId('disable-usage-report-banner')).not.toBeInTheDocument()
      act(() => {
        screen.getByText('Get usage report').click()
      })
      await expect(
        screen.getByRole('button', {
          name: /Email usage report/i,
        }),
      ).toBeDisabled()
    })
  })

  describe('custom date range usage report and UI changes', () => {
    test('renders custom date range usage report option when show_custom_date_range_usage_report ff is true', async () => {
      const {user} = render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_CUSTOM_RANGE_SELECTIONS}
          billingPlatformEnabledProducts={['Actions']}
          showCustomDateRangeUsageReport
          minCustomDate="2024-11-11"
        />,
      )

      await user.click(screen.getByText('Get usage report'))
      expect(
        screen.getByText("The usage report will be emailed when it's ready to test@github.com."),
      ).toBeInTheDocument()
      expect(screen.getByText('Select time frame:')).toBeInTheDocument()
      expect(screen.getByText('Custom range')).toBeInTheDocument()
      await user.click(screen.getByText('Custom range'))
      expect(screen.getByText('Choose date...')).toBeInTheDocument()
      expect(screen.getByText('Up to 31 days')).toBeInTheDocument()
      expect(
        screen.getByRole('button', {
          name: /Email me the report/i,
        }),
      ).toBeEnabled()
      expect(
        screen.getByRole('button', {
          name: /Cancel/i,
        }),
      ).toBeInTheDocument()
      expect(screen.getByText('A detailed report will be generated including your metered usage.')).toBeInTheDocument()
    })

    test('legacy usage option UI changes', async () => {
      const {user} = render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS_WITH_LEGACY}
          billingPlatformEnabledProducts={['Actions']}
          showCustomDateRangeUsageReport
          vnextMigrationDate="November 1, 2024"
          minCustomDate="2024-11-01"
        />,
      )

      await user.click(screen.getByText('Get usage report'))
      expect(
        screen.getByText("The usage report will be emailed when it's ready to test@github.com."),
      ).toBeInTheDocument()
      expect(screen.getByText('Select time frame:')).toBeInTheDocument()
      expect(screen.getByText('A detailed report will be generated including your metered usage.')).toBeInTheDocument()
      expect(screen.getByText('Legacy usage')).toBeInTheDocument()
      expect(
        screen.getByText(
          `Get a usage report for days before November 1, 2024, before your organization transitioned to the enhanced billing platform.`,
        ),
      ).toBeInTheDocument()
    })

    test('shows an error banner when custom range option is selected and user submits without selecting dates', async () => {
      // Note: this error occurs due to our usage of `@container` within a
      // `<style>` tag in Banner. The CSS parser for jsdom does not support this
      // syntax and will fail with an error containing the message below.
      // Tracking issue: https://github.com/github/primer/issues/3882
      // eslint-disable-next-line no-console
      const originalConsoleError = console.error
      jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
        if (!value?.message?.includes('Could not parse CSS stylesheet')) {
          originalConsoleError(value, ...args)
        }
      })

      const {user} = render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_CUSTOM_RANGE_SELECTIONS}
          billingPlatformEnabledProducts={['Actions']}
          showCustomDateRangeUsageReport
          minCustomDate="2024-11-11"
        />,
      )
      await user.click(screen.getByText('Get usage report'))
      await user.click(screen.getByText('Custom range'))
      await user.click(screen.getByRole('button', {name: /Email me the report/i}))

      expect(screen.getByTestId('error-validation-banner')).toBeInTheDocument()
      expect(screen.getByText('Specify a custom date range')).toBeInTheDocument()
    })
  })
})
