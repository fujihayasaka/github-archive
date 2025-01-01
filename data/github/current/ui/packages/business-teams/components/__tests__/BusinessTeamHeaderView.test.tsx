import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {BusinessTeamHeaderView} from '../BusinessTeamHeaderView'
import {getBusinessTeamHeaderViewProps, getBusinessTeamHeaderNoAssignmentPermissions} from '../../test-utils/mock-data'

jest.useFakeTimers()
const mockNavigate = jest.fn()
jest.mock('@github-ui/use-navigate', () => {
  return {
    useNavigate: () => mockNavigate,
  }
})

test('renders header for given team', () => {
  const props = getBusinessTeamHeaderViewProps()
  render(<BusinessTeamHeaderView {...props} />)

  // breadcrumbs
  const breadcrumbTeamsLink = screen.getByTestId('breadcrumb-teams-link')
  expect(breadcrumbTeamsLink).toHaveAttribute('href', `/enterprises/${props.enterpriseSlug}/teams`)
  const breadcrumbTeamName = screen.getByTestId('breadcrumb-team-name')
  expect(breadcrumbTeamName).toBeInTheDocument()

  // stack
  const overviewTeamName = screen.getByTestId('overview-team-name')
  expect(overviewTeamName).toHaveTextContent(props.enterpriseTeam.name)
  const overviewTeamDescription = screen.getByTestId('overview-team-description')
  expect(overviewTeamDescription).toHaveTextContent(props.enterpriseTeam.description)
  const editButton = screen.getByRole('button', {name: 'Edit'})
  expect(editButton).toBeVisible()

  // underline nav (tabs)
  const membersTab = screen.getByTestId('nav-Members')
  expect(membersTab).toHaveAttribute(
    'href',
    `/enterprises/${props.enterpriseSlug}/teams/${props.enterpriseTeam.slug}/members`,
  )
  expect(membersTab).toHaveTextContent('Members2 (2)')
  const rolesTab = screen.getByTestId('nav-Assigned roles')
  expect(rolesTab).toHaveAttribute(
    'href',
    `/enterprises/${props.enterpriseSlug}/teams/${props.enterpriseTeam.slug}/roles`,
  )
  expect(rolesTab).toHaveTextContent('Assigned roles3 (3)')
})

test('does not render assignment tab when permissions do not allow', () => {
  const props = getBusinessTeamHeaderNoAssignmentPermissions()
  render(<BusinessTeamHeaderView {...props} />)

  // breadcrumbs
  const breadcrumbTeamsLink = screen.getByTestId('breadcrumb-teams-link')
  expect(breadcrumbTeamsLink).toHaveAttribute('href', `/enterprises/${props.enterpriseSlug}/teams`)
  const breadcrumbTeamName = screen.getByTestId('breadcrumb-team-name')
  expect(breadcrumbTeamName).toBeInTheDocument()

  // stack
  const overviewTeamName = screen.getByTestId('overview-team-name')
  expect(overviewTeamName).toHaveTextContent(props.enterpriseTeam.name)
  const overviewTeamDescription = screen.getByTestId('overview-team-description')
  expect(overviewTeamDescription).toHaveTextContent(props.enterpriseTeam.description)
  const editButton = screen.getByRole('button', {name: 'Edit'})
  expect(editButton).toBeVisible()

  // underline nav (tabs)
  const membersTab = screen.getByTestId('nav-Members')
  expect(membersTab).toHaveAttribute(
    'href',
    `/enterprises/${props.enterpriseSlug}/teams/${props.enterpriseTeam.slug}/members`,
  )
  expect(membersTab).toHaveTextContent('Members2 (2)')
  expect(screen.queryByTestId('nav-Assigned roles')).not.toBeInTheDocument()
})

test('Edit button navigates to edit team', async () => {
  const props = getBusinessTeamHeaderViewProps()
  const {user} = render(<BusinessTeamHeaderView {...props} />)

  const editButton = screen.getByRole('button', {name: 'Edit'})
  expect(editButton).toBeInTheDocument()

  await user.click(editButton)

  expect(mockNavigate).toHaveBeenCalledWith(`/enterprises/acme-corp/teams/acme-engineering/edit`)
})

test('Current page is marked in underline nav - members', () => {
  const props = getBusinessTeamHeaderViewProps()
  props.currentView = 'Members'
  render(<BusinessTeamHeaderView {...props} />)

  const membersTab = screen.getByTestId('nav-Members')
  expect(membersTab).toHaveAttribute('aria-current', 'page')
})

test('Current page is marked in underline nav - roles', () => {
  const props = getBusinessTeamHeaderViewProps()
  props.currentView = 'Assigned roles'
  render(<BusinessTeamHeaderView {...props} />)

  const rolesTab = screen.getByTestId('nav-Assigned roles')
  expect(rolesTab).toHaveAttribute('aria-current', 'page')
})

test('Current page is marked in underline nav - orgs', () => {
  const props = getBusinessTeamHeaderViewProps()
  props.currentView = 'Organizations'
  render(<BusinessTeamHeaderView {...props} />)

  const orgsTab = screen.getByTestId('nav-Organizations')
  expect(orgsTab).toHaveAttribute('aria-current', 'page')
})

test('Shows "All" in the Organizations tab when organizationSelectionType is "all"', () => {
  const props = getBusinessTeamHeaderViewProps()
  props.enterpriseTeam.organizationSelectionType = 'all'
  props.currentView = 'Organizations'

  render(<BusinessTeamHeaderView {...props} />)

  const orgsTab = screen.getByTestId('nav-Organizations')
  expect(orgsTab).toHaveTextContent('OrganizationsAll (All)')
})

test('displays IdP group label when externalGroup is present', () => {
  const props = getBusinessTeamHeaderViewProps()
  props.enterpriseTeam.linkedToExternalGroup = true
  render(<BusinessTeamHeaderView {...props} />)

  const idpGroupLabel = screen.getByTestId('idp-group-label')
  expect(idpGroupLabel).toBeInTheDocument()
  expect(idpGroupLabel).toHaveTextContent('IdP group')
})

test('does not display IdP group label when externalGroup is not present', () => {
  const props = getBusinessTeamHeaderViewProps()
  props.enterpriseTeam.linkedToExternalGroup = false
  render(<BusinessTeamHeaderView {...props} />)

  expect(screen.queryByTestId('idp-group-label')).not.toBeInTheDocument()
})
