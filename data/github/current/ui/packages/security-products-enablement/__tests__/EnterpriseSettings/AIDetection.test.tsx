import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import type {AIDetectionProps} from '../../components/EnterpriseSettings/AdditionalSettings/SecretScanning/AIDetection'
import {getEnterpriseSettingsRoutePayload} from '../../test-utils/mock-data'
import AIDetection from '../../components/EnterpriseSettings/AdditionalSettings/SecretScanning/AIDetection'
import App from '../../App'
import {mockFetch} from '@github-ui/mock-fetch'

function TestComponent(props: AIDetectionProps) {
  return (
    <App>
      <AIDetection {...props} />
    </App>
  )
}

// Helper function to find the span near the <ControlGroup.ToggleSwitch> component.
// This is necessary because currently the data-testid prop is only set on the div enclosing the button and not the value itself.
function findCurrentValue(toggle: HTMLElement) {
  return toggle.parentNode?.querySelector('span')
}

describe('AIDetection', () => {
  it('does not render the setting if it is not available', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    routePayload.additionalSettings.aiDetection = null

    const props: AIDetectionProps = {value: null}

    render(TestComponent(props), {routePayload})

    expect(screen.queryByTestId('ai-detection-toggle')).not.toBeInTheDocument()
  })

  it('renders the setting if it available', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    const props: AIDetectionProps = {value: routePayload.additionalSettings.aiDetection}

    render(TestComponent(props), {routePayload})

    expect(screen.getByTestId('ai-detection-toggle')).toBeInTheDocument()
  })

  it('updates the toggle value', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    const props: AIDetectionProps = {value: routePayload.additionalSettings.aiDetection}

    const {user} = render(TestComponent(props), {routePayload})

    let toggle = screen.getByTestId('ai-detection-toggle')
    expect(toggle).toBeInTheDocument()

    const mockRequest = mockFetch.mockRouteOnce(
      '/enterprises/github-inc/settings/security_analysis/ai_detection',
      {secret_scanning_generic_secrets: 'disabled'},
      {
        ok: true,
        status: 202,
        json: async () => {
          return {success: true}
        },
      },
    )

    await user.click(screen.getByRole('button'))
    expect(mockRequest).toHaveBeenCalledTimes(1)

    toggle = screen.getByTestId('ai-detection-toggle')
    const currentValue = findCurrentValue(toggle)
    expect(currentValue).not.toBeChecked()
  })
})
