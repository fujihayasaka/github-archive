import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {BusinessTeamOrganizationsView} from '../routes/BusinessTeamOrganizationsView'
import {getBusinessTeamOrganizationsViewRoutePayload} from '../test-utils/mock-data'

test('Renders header with orgs tab selected', () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  render(<BusinessTeamOrganizationsView />, {
    routePayload,
  })

  // assert any content from header
  expect(screen.getByTestId('overview-team-name')).toBeInTheDocument()

  const orgsTab = screen.getByTestId('nav-Organizations')
  expect(orgsTab).toHaveAttribute('aria-current', 'page')
  expect(orgsTab).toHaveTextContent(routePayload.enterpriseTeam.totalOrganizationCount.toString())
})

test('Renders the BusinessTeamOrganizationsView with orgs', () => {
  const routePayload = getBusinessTeamOrganizationsViewRoutePayload()
  render(<BusinessTeamOrganizationsView />, {
    routePayload,
  })

  const firstOrg = screen.getByTestId('list-item-1')
  expect(firstOrg).toBeVisible()
  expect(within(firstOrg).getByTestId('list-view-item-title-container')).toHaveTextContent('A first org')
  expect(within(firstOrg).getByTestId('list-view-item-description')).toHaveTextContent('The first org')

  const secondOrg = screen.getByTestId('list-item-2')
  expect(secondOrg).toBeVisible()
  expect(within(secondOrg).getByTestId('list-view-item-title-container')).toHaveTextContent('The other org')
})
