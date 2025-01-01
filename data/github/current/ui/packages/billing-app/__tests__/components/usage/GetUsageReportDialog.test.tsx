import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {GetUsageReportDialog} from '../../../components/usage'
import {
  USAGE_REPORT_CUSTOM_RANGE_SELECTIONS,
  USAGE_REPORT_SELECTIONS,
  USAGE_REPORT_SELECTIONS_WITH_LEGACY,
} from '../../../test-utils/mock-data'

describe('GetUsageReportDialog.Trigger', () => {
  test('Opens dialog when usage report button clicked', async () => {
    render(
      <GetUsageReportDialog.Trigger
        currentUserEmail="test@github.com"
        usageReportSelections={USAGE_REPORT_SELECTIONS}
        minCustomDate="2024-11-11"
        codingAgentEnabled={false}
        sparkEnabled={false}
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
      <GetUsageReportDialog.Trigger
        currentUserEmail="test@github.com"
        usageReportSelections={USAGE_REPORT_SELECTIONS}
        minCustomDate="2024-11-11"
        codingAgentEnabled={false}
        sparkEnabled={false}
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
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS_WITH_LEGACY}
          vnextMigrationDate="Aug 1, 2022"
          minCustomDate="2024-11-11"
          codingAgentEnabled={false}
          sparkEnabled={false}
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
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          disableUsageReports
          minCustomDate="2024-11-11"
          codingAgentEnabled={false}
          sparkEnabled={false}
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
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          disableUsageReports
          minCustomDate="2024-11-11"
          codingAgentEnabled={false}
          sparkEnabled={false}
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
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_CUSTOM_RANGE_SELECTIONS}
          minCustomDate="2024-11-11"
          codingAgentEnabled={false}
          sparkEnabled={false}
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
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS_WITH_LEGACY}
          vnextMigrationDate="November 1, 2024"
          minCustomDate="2024-11-01"
          codingAgentEnabled={false}
          sparkEnabled={false}
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
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_CUSTOM_RANGE_SELECTIONS}
          minCustomDate="2024-11-11"
          codingAgentEnabled={false}
          sparkEnabled={false}
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
    const MORE_OPTIONS_LABEL = 'More options'

    test('does not render the option if Copilot overages are not enabled', async () => {
      render(
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          minCustomDate="2024-11-11"
          codingAgentEnabled={false}
          sparkEnabled={false}
        />,
      )

      expect(screen.queryByLabelText(MORE_OPTIONS_LABEL)).toBeNull()
    })

    test('renders the option if Copilot overages are enabled', async () => {
      const {user} = render(
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          minCustomDate="2024-11-11"
          copilotPremiumReportEnabled
          codingAgentEnabled={false}
          sparkEnabled={false}
        />,
      )

      await user.click(screen.getByLabelText(MORE_OPTIONS_LABEL))

      expect(screen.getByText('Copilot premium requests usage report')).toBeInTheDocument()
    })

    test('opens the standard usage report dialog by default', async () => {
      const {user} = render(
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          minCustomDate="2024-11-11"
          copilotPremiumReportEnabled
          codingAgentEnabled={false}
          sparkEnabled={false}
        />,
      )

      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

      await user.click(screen.getByText('Get usage report'))

      expect(screen.getByRole('dialog')).toBeVisible()
      expect(screen.queryByText('Custom range')).not.toBeInTheDocument()
    })
  })

  describe('Copilot premium requests text', () => {
    const MORE_OPTIONS_LABEL = 'More options'
    test('renders the default premium request text', async () => {
      const {user} = render(
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          minCustomDate="2024-11-11"
          copilotPremiumReportEnabled
          codingAgentEnabled={false}
          sparkEnabled={false}
        />,
      )

      await user.click(screen.getByLabelText(MORE_OPTIONS_LABEL))

      expect(
        screen.getByText(
          'Provides a per user breakdown of requests exhausted and their monthly quota for the current billing period.',
        ),
      ).toBeInTheDocument()
    })

    test('renders the default copilot coding agent premium request text', async () => {
      const {user} = render(
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          minCustomDate="2024-11-11"
          copilotPremiumReportEnabled
          codingAgentEnabled
          sparkEnabled={false}
        />,
      )

      await user.click(screen.getByLabelText(MORE_OPTIONS_LABEL))

      expect(
        screen.getByText(
          'Provides a per-user breakdown of Copilot and Copilot coding agent premium requests for the current billing period.',
        ),
      ).toBeInTheDocument()
    })

    test('renders the default spark premium request text', async () => {
      const {user} = render(
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          minCustomDate="2024-11-11"
          copilotPremiumReportEnabled
          codingAgentEnabled={false}
          sparkEnabled
        />,
      )

      await user.click(screen.getByLabelText(MORE_OPTIONS_LABEL))

      expect(
        screen.getByText(
          'Provides a per-user breakdown of Copilot and Spark premium requests for the current billing period.',
        ),
      ).toBeInTheDocument()
    })

    test('renders the default copilot coding agent and spark premium request text', async () => {
      const {user} = render(
        <GetUsageReportDialog.Trigger
          currentUserEmail="test@github.com"
          usageReportSelections={USAGE_REPORT_SELECTIONS}
          minCustomDate="2024-11-11"
          copilotPremiumReportEnabled
          codingAgentEnabled
          sparkEnabled
        />,
      )

      await user.click(screen.getByLabelText(MORE_OPTIONS_LABEL))

      expect(
        screen.getByText(
          'Provides a per-user breakdown of Copilot, Spark, and Copilot coding agent premium requests for the current billing period.',
        ),
      ).toBeInTheDocument()
    })
  })
})
