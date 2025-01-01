import {screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {enterpriseOrgs, esmRole, getNewRoleAssignmentListProps, noFgpsRole} from '../test-utils/mock-data'
import {NewRoleAssignmentList, type NewRoleAssignmentListProps} from '../components/NewRoleAssignmentList'

const ESM_DISABLED_FOR_USER_TEXT = 'Unavailable: includes repository or org-level permissions'
const ESM_DISABLED_FOR_BUSINESS_TEAMS_TEXT = 'Unavailable: Enterprise Teams organization limit exceeded'

test('Renders RoleAssignmentList', () => {
  const props = getNewRoleAssignmentListProps()
  render(<NewRoleAssignmentList {...props} />)

  const listHeader = screen.getByRole('heading', {level: 4, name: `${props.roles.length} roles`})
  expect(listHeader).toBeInTheDocument()
  const list = screen.getByRole('menu')
  expect(list).toBeInTheDocument()
  const listItems = screen.getAllByRole('menuitemradio')
  expect(listItems).toHaveLength(props.roles.length)
})

// test for some structure relied on in RoleAssignmentList.module.css
// we use the CSS selector `:has(> .rolesListHeading)` to apply a rounded box shape to the table header container
// if this test fails, that means that Primer has changed the HTML structure of ActionList.GroupHeading
// and the RoleAssignmentList heading (structure or CSS) should be updated to retain the table header appearance
test('rolesListHeading div styling', () => {
  const props = getNewRoleAssignmentListProps()
  render(<NewRoleAssignmentList {...props} />)

  const listHeader = screen.getByRole('heading', {level: 4, name: `${props.roles.length} roles`})
  expect(listHeader).toBeInTheDocument()
  // eslint-disable-next-line testing-library/no-node-access
  const headerParent = listHeader.parentElement
  expect(headerParent).toBeInstanceOf(HTMLDivElement)
})

test('clicking a role calls callback prop w/ that role id', async () => {
  const props = getNewRoleAssignmentListProps()
  const {user} = render(<NewRoleAssignmentList {...props} />)

  const role1 = screen.getByRole('menuitemradio', {name: props.roles[0]!.name})
  expect(role1).toBeInTheDocument()
  const role2 = screen.getByRole('menuitemradio', {name: props.roles[1]!.name})
  expect(role2).toBeInTheDocument()

  await user.click(role1)
  expect(props.onSelectCallback).toHaveBeenCalledWith(props.roles[0]!.id)

  await user.click(role2)
  expect(props.onSelectCallback).toHaveBeenCalledWith(props.roles[1]!.id)
})

test('does not display role disabled text when assignee is unselected and org limit for teams has not exceeded', () => {
  const props = getNewRoleAssignmentListProps()
  render(<NewRoleAssignmentList {...props} />)

  expect(screen.queryByText(ESM_DISABLED_FOR_USER_TEXT)).not.toBeInTheDocument()
  expect(screen.queryByText(ESM_DISABLED_FOR_BUSINESS_TEAMS_TEXT)).not.toBeInTheDocument()
})

test('disables ESM role selection when assignee is a user', async () => {
  const props: NewRoleAssignmentListProps = {
    roles: [esmRole, noFgpsRole],
    assigneeType: 'user',
    selectedRoleId: null,
    onSelectCallback: jest.fn(),
  }
  const {user} = render(<NewRoleAssignmentList {...props} />)

  const role1 = screen.getByRole('menuitemradio', {name: props.roles[0]!.name})
  expect(role1).toBeInTheDocument()
  expect(role1).toHaveTextContent(ESM_DISABLED_FOR_USER_TEXT)
  const role2 = screen.getByRole('menuitemradio', {name: props.roles[1]!.name})
  expect(role2).toBeInTheDocument()
  expect(role2).not.toHaveTextContent(ESM_DISABLED_FOR_USER_TEXT)

  await user.click(role1)
  expect(props.onSelectCallback).not.toHaveBeenCalledWith(props.roles[0]!.id)
})

test('disables ESM role selection when enterprise has reached the org limit for enterprise teams', async () => {
  const props: NewRoleAssignmentListProps = {
    roles: [esmRole, noFgpsRole],
    assigneeType: 'businessteam',
    enterpriseTeamOrgAssignmentLimitExceeded: true,
    selectedRoleId: null,
    onSelectCallback: jest.fn(),
  }
  const {user} = render(<NewRoleAssignmentList {...props} />)

  const role1 = screen.getByRole('menuitemradio', {name: props.roles[0]!.name})
  expect(role1).toBeInTheDocument()
  expect(role1).toHaveTextContent(ESM_DISABLED_FOR_BUSINESS_TEAMS_TEXT)

  await user.click(role1)
  expect(props.onSelectCallback).not.toHaveBeenCalledWith(props.roles[0]!.id)
})

test('displays AvatarStack only for an esm role', () => {
  const props = getNewRoleAssignmentListProps()
  render(<NewRoleAssignmentList {...props} enterpriseOrgs={enterpriseOrgs} />)

  // Expect only 2 avatars
  expect(screen.getAllByTestId('enterprise-org-avatar')).toHaveLength(2)

  // Expect them to be in ESM role
  const esm = screen.getByRole('menuitemradio', {name: props.roles[3]!.name})
  expect(esm).toBeInTheDocument()

  const avatars = within(esm).getAllByTestId('enterprise-org-avatar')
  expect(avatars).toHaveLength(2)
})

test('does not display AvatarStack when there is no esm role', () => {
  const props: NewRoleAssignmentListProps = {
    roles: [noFgpsRole],
    assigneeType: null,
    enterpriseOrgs,
    selectedRoleId: null,
    onSelectCallback: jest.fn(),
  }
  render(<NewRoleAssignmentList {...props} />)

  expect(screen.queryAllByRole('enterprise-org-avatar')).toHaveLength(0)
})

test('does not display AvatarStack when enterpriseOrgs are not provided for an ESM role', () => {
  const props: NewRoleAssignmentListProps = {
    roles: [esmRole],
    assigneeType: null,
    selectedRoleId: null,
    onSelectCallback: jest.fn(),
  }
  render(<NewRoleAssignmentList {...props} />)

  expect(screen.queryAllByRole('enterprise-org-avatar')).toHaveLength(0)
})
