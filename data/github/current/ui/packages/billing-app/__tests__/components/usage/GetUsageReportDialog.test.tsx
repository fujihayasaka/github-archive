import {act, screen} from '@testing-library/react'

import {isFeatureEnabled} from '@github-ui/feature-flags'
import {render} from '@github-ui/react-core/test-utils'

import {GetUsageReportDialog} from '../../../components/usage'

import {
  USAGE_REPORT_CUSTOM_RANGE_SELECTIONS,
  USAGE_REPORT_SELECTIONS,
  USAGE_REPORT_SELECTIONS_WITH_LEGACY,
} from '../../../test-utils/mock-data'

jest.mock('@github-ui/feature-flags', () => ({
  isFeatureEnabled: jest.fn(),
}))

const mockIsFeatureEnabled = jest.mocked(isFeatureEnabled)

describe('GetUsageReportDialog', () => {
  test('Opens dialog when usage report button clicked', async () => {
    render(
      <GetUsageReportDialog
        currentUserEmail="test@github.com"
        usageReportSelections={USAGE_REPORT_SELECTIONS}
        minCustomDate="2024-11-11"
      />,
    )

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    act(() => {
      screen.getByText('Get usage report').click()
    })
    expect(screen.getByRole('dialog')).toBeVisible()
    expect(screen.queryByText('Custom range')).not.toBeInTheDocument()
  })

  test('usage report copy', async () => {
    render(
      <GetUsageReportDialog
        currentUserEmail="test@github.com"
        usageReportSelections={USAGE_REPORT_SELECTIONS}
        minCustomDate="2024-11-11"
      />,
    )

    expect(screen.queryByTestId('usage-report-dialog-header')).not.toBeInTheDocument()
    act(() => {
      screen.getByText('Get usage report').click()
    })

    expect(
      screen.getByText(/A detailed report will be generated of your metered usage, with all times reported in UTC./),
    ).toBeInTheDocument()
  })

  describe('legacy report option', () => {
    test('hide vnext text when legacy report is clicked', async () => {
      const {user} = render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS_WITH_LEGACY}
          vnextMigrationDate="Aug 1, 2022"
          minCustomDate="2024-11-11"
        />,
      )

      await user.click(screen.getByText('Get usage report'))
      await user.click(screen.getByText('Legacy usage'))

      expect(
        screen.queryByText(
          /A detailed report will be generated of your metered usage, with all times reported in UTC./,
        ),
      ).not.toBeInTheDocument()
    })
  })

  describe('disabled usage reports', () => {
    test('Renders alert banner when usage reports are disabled', async () => {
      render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          disableUsageReports
          minCustomDate="2024-11-11"
        />,
      )

      expect(screen.queryByTestId('disable-usage-report-banner')).not.toBeInTheDocument()
      act(() => {
        screen.getByText('Get usage report').click()
      })
      expect(screen.getByTestId('disable-usage-report-banner')).toBeInTheDocument()
    })

    test('Disable button when usage reports are disabled', async () => {
      render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          disableUsageReports
          minCustomDate="2024-11-11"
        />,
      )

      expect(screen.queryByTestId('disable-usage-report-banner')).not.toBeInTheDocument()
      act(() => {
        screen.getByText('Get usage report').click()
      })
      expect(
        screen.getByRole('button', {
          name: /Email me the report/i,
        }),
      ).toBeDisabled()
    })
  })

  describe('custom date range usage report and UI changes', () => {
    test('renders custom date range usage report option', async () => {
      const {user} = render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_CUSTOM_RANGE_SELECTIONS}
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
      expect(
        screen.getByText('A detailed report will be generated of your metered usage, with all times reported in UTC.'),
      ).toBeInTheDocument()
    })

    test('legacy usage option UI changes', async () => {
      const {user} = render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS_WITH_LEGACY}
          vnextMigrationDate="November 1, 2024"
          minCustomDate="2024-11-01"
        />,
      )

      await user.click(screen.getByText('Get usage report'))
      expect(
        screen.getByText("The usage report will be emailed when it's ready to test@github.com."),
      ).toBeInTheDocument()
      expect(screen.getByText('Select time frame:')).toBeInTheDocument()
      expect(
        screen.getByText('A detailed report will be generated of your metered usage, with all times reported in UTC.'),
      ).toBeInTheDocument()
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

  describe('handling Copilot overages custom usage report', () => {
    test('does not render the option if the feature flag is disabled', async () => {
      mockIsFeatureEnabled.mockReturnValue(false)

      render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          minCustomDate="2024-11-11"
          copilotPremiumReportEnabled
        />,
      )

      expect(screen.queryByLabelText('More options')).toBeNull()
    })

    test('does not render the option if Copilot overages are not enabled', async () => {
      mockIsFeatureEnabled.mockReturnValue(true)

      render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          minCustomDate="2024-11-11"
          copilotPremiumReportEnabled={false}
        />,
      )

      expect(screen.queryByLabelText('More options')).toBeNull()
    })

    test('renders the option if Copilot overages are enabled', async () => {
      mockIsFeatureEnabled.mockReturnValue(true)

      const {user} = render(
        <GetUsageReportDialog
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          minCustomDate="2024-11-11"
          copilotPremiumReportEnabled
        />,
      )

      await user.click(screen.getByLabelText('More options'))

      expect(screen.getByText('Copilot premium requests usage report')).toBeInTheDocument()
    })
  })
})
