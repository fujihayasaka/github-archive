import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import SecurityConfigurationTable from '../../components/SecurityConfiguration/Table'
import {getOrganizationSettingsSecurityProductsRoutePayload} from '../../test-utils/mock-data'
import {AliveTestProvider} from '@github-ui/use-alive/test-utils'
import App from '../../App'
import {swallowCSSParsingError} from '../../test-utils/test-helper'
import {navigateFn, setupNavigateMock} from '../test-helpers'

jest.mock('@github-ui/use-navigate', () => {
  const actual = jest.requireActual('@github-ui/use-navigate')
  return {
    ...actual,
    useNavigate: () => navigateFn,
  }
})

setupNavigateMock()
beforeEach(swallowCSSParsingError)

describe('SecurityConfigurationTable', () => {
  it('lists the github recommend config plus the 2 custom security configurations if not enterprise owned', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    routePayload.capabilities.enterpriseOwned = false
    routePayload.githubRecommendedConfiguration!.enforcement = 'enforced'
    render(
      <App>
        <AliveTestProvider>
          <SecurityConfigurationTable tableType="organization" header="Configurations" />
        </AliveTestProvider>
      </App>,
      {routePayload},
    )

    expect(screen.getByText('GitHub recommended')).toBeInTheDocument()
    expect(screen.getByText('Enforced')).toBeInTheDocument()
    expect(screen.getByText('5 repositories')).toBeInTheDocument()
    expect(
      screen.getByText('Suggested settings for Dependabot, secret scanning, and code scanning.'),
    ).toBeInTheDocument()

    expect(screen.getByText('High Risk')).toBeInTheDocument()
    expect(screen.getByText('10 repositories')).toBeInTheDocument()
    expect(screen.getByText('Use for our critical repos')).toBeInTheDocument()

    expect(screen.getByText('Low Risk')).toBeInTheDocument()
    expect(screen.getByText('1 repository')).toBeInTheDocument()
    expect(screen.getByText('Always use this for our empty repos')).toBeInTheDocument()
    expect(screen.queryByText('Apply configuration')).not.toBeInTheDocument()
    expect(screen.queryByText('Low Risk Enterprise')).not.toBeInTheDocument()
  })

  it('lists the github recommend config and enterprise but not the 2 custom security configurations if enterprise owned', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(
      <App>
        <AliveTestProvider>
          <SecurityConfigurationTable tableType="enterprise" header="Enterprise configurations" />
        </AliveTestProvider>
      </App>,
      {routePayload},
    )

    expect(screen.getByText('GitHub recommended')).toBeInTheDocument()
    expect(screen.getByText('5 repositories')).toBeInTheDocument()
    expect(
      screen.getByText('Suggested settings for Dependabot, secret scanning, and code scanning.'),
    ).toBeInTheDocument()
    expect(screen.getByText('Low Risk Enterprise')).toBeInTheDocument()
    expect(screen.queryByText('High Risk')).not.toBeInTheDocument()
    expect(screen.queryByText('Low Risk')).not.toBeInTheDocument()
  })

  it('does not render the GitHub recommended configuration if it is not present', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    render(
      <App>
        <AliveTestProvider>
          <SecurityConfigurationTable tableType="organization" header="Configurations" />
        </AliveTestProvider>
      </App>,
      {routePayload},
    )

    expect(screen.getByText('High Risk')).toBeInTheDocument()
    expect(screen.getByText('10 repositories')).toBeInTheDocument()
    expect(screen.queryByText('GitHub recommended')).not.toBeInTheDocument()
  })

  it('does not render GitHub Advanced Security label if organization has not purchased GHAS', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    routePayload.capabilities.ghasPurchased = false
    routePayload.capabilities.enterpriseOwned = false
    render(
      <App>
        <SecurityConfigurationTable tableType="organization" header="Configurations" />
      </App>,
      {routePayload},
    )

    const element = screen.getByTestId(`configuration-${routePayload.githubRecommendedConfiguration?.id}`)
    expect(element).not.toHaveTextContent('GitHub Advanced Security')
  })

  it('does renders GitHub Advanced Security label if organization has purchased GHAS', async () => {
    const routePayload = getOrganizationSettingsSecurityProductsRoutePayload()
    routePayload.capabilities.enterpriseOwned = false
    render(
      <App>
        <SecurityConfigurationTable tableType="organization" header="Configurations" />
      </App>,
      {routePayload},
    )

    const element = screen.getByTestId(`configuration-${routePayload.githubRecommendedConfiguration?.id}`)
    expect(element).toHaveTextContent('GitHub Advanced Security')
  })
})
