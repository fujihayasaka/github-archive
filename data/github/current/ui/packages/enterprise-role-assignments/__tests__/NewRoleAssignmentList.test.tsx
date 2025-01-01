import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {getNewRoleAssignmentListProps} from '../test-utils/mock-data'
import {NewRoleAssignmentList} from '../components/NewRoleAssignmentList'

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
