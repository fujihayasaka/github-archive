import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {getEnterpriseSettingsRoutePayload} from '../../test-utils/mock-data'
import ResourceLinks, {
  type ResourceLinksProps,
} from '../../components/EnterpriseSettings/AdditionalSettings/SecretScanning/ResourceLinks'
import App from '../../App'

function TestComponent(props: ResourceLinksProps) {
  return (
    <App>
      <ResourceLinks {...props} />
    </App>
  )
}

// Helper function to find the span near the <ControlGroup.InlineEdit> component.
// This is necessary because currently the data-testid prop is only set on the edit button and not the value itself.
function findCurrentValue(editButton: HTMLElement) {
  return editButton.parentNode?.querySelector('span')
}

describe('ResourceLinks', () => {
  it('does not render a resource link if it is unset', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    const props: ResourceLinksProps = {value: routePayload.additionalSettings.resourceLink}
    render(TestComponent(props), {routePayload})

    const editButton = screen.getByTestId('edit-resource-link')
    expect(editButton).toBeInTheDocument()

    const currentValue = findCurrentValue(editButton)
    expect(currentValue).toBeEmptyDOMElement()
  })

  it('renders the current resource link if it is set', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    const expectedLink = 'https://gh.io/help-me'
    const props: ResourceLinksProps = {value: expectedLink}
    render(TestComponent(props), {routePayload})

    const editButton = screen.getByTestId('edit-resource-link')
    expect(editButton).toBeInTheDocument()

    const currentValue = findCurrentValue(editButton)
    expect(currentValue).toHaveTextContent(expectedLink)
  })

  it('renders a text box when the edit button is clicked', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    const expectedLink = 'https://gh.io/help-me'
    const props: ResourceLinksProps = {value: expectedLink}
    const {user} = render(TestComponent(props), {routePayload})

    const editButton = screen.getByTestId('edit-resource-link')
    expect(editButton).toBeInTheDocument()
    await user.click(editButton)

    const textBox = screen.getByRole('textbox')
    expect(textBox).toBeInTheDocument()
    expect(textBox).toHaveValue(expectedLink)
  })

  it('persists edited link', async () => {
    const routePayload = getEnterpriseSettingsRoutePayload()
    const {user} = render(TestComponent({value: null}), {routePayload})

    let editButton = screen.getByTestId('edit-resource-link')
    expect(editButton).toBeInTheDocument()
    await user.click(editButton)

    const textBox = screen.getByRole('textbox')
    expect(textBox).toBeInTheDocument()

    const expectedUserInput = 'https://gh.io/help-me'
    const mockRequest = mockFetch.mockRouteOnce(
      '/enterprises/github-inc/settings/security_analysis/resource_link',
      {input: expectedUserInput},
      {
        ok: true,
        status: 202,
        json: async () => {
          return {success: true}
        },
      },
    )
    await user.type(textBox, expectedUserInput)
    await user.click(screen.getByRole('button', {name: 'Save'}))
    expect(mockRequest).toHaveBeenCalledTimes(1)

    editButton = screen.getByTestId('edit-resource-link')
    const currentValue = findCurrentValue(editButton)
    expect(currentValue).toHaveTextContent(expectedUserInput)
  })
})
