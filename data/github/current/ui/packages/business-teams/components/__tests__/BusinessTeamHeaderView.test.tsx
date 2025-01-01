import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {BusinessTeamHeaderView} from '../BusinessTeamHeaderView'
import {getBusinessTeamHeaderViewProps} from '../../test-utils/mock-data'

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
