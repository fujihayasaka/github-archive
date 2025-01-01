import {screen, within} from '@testing-library/react'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
import CopilotMetricsInfoDialog, {type HelpLink} from '../components/CopilotMetricsInfoDialog'

const userEvent = setupUserEvent()

const mockCopilotMetricsInfoDialogHelpLinks: HelpLink[] = [
  {text: 'Learn more here', url: 'https://example.com/learn'},
  {text: 'Another link', url: 'https://example.com/another'},
]

const renderDialog = (header?: string, text?: string, helpLinks?: HelpLink[]) =>
  render(
    <CopilotMetricsInfoDialog
      dialogHeader={header || 'This is a dialog header'}
      dialogText={text || 'This is the dialog body text'}
      helpLinks={helpLinks || mockCopilotMetricsInfoDialogHelpLinks}
    />,
  )

describe('CopilotMetricsInfoDialog', () => {
  it('renders the info button but not the dialog by default', () => {
    renderDialog()
    expect(screen.getByTestId('copilot-metrics-info-button')).toBeInTheDocument()
    expect(screen.queryByTestId('copilot-metrics-info-dialog')).not.toBeInTheDocument()
  })

  it('displays popover with correct links after clicking info button', async () => {
    renderDialog()
    const iconButton = screen.getByTestId('copilot-metrics-info-button')

    expect(screen.queryByTestId('copilot-metrics-info-dialog')).not.toBeInTheDocument()

    await userEvent.click(iconButton)

    const dialog = await screen.findByTestId('copilot-metrics-info-dialog')
    const withinDialog = within(dialog)

    expect(withinDialog.getByText('This is a dialog header')).toBeVisible()

    for (const link of mockCopilotMetricsInfoDialogHelpLinks) {
      const anchor = withinDialog.getByRole('link', {name: link.text})
      expect(anchor).toBeVisible()
      expect(anchor).toHaveAttribute('href', link.url)
    }
  })
})
