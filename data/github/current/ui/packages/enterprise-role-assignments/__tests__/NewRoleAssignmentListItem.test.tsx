import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {getNewRoleAssignmentListItemProps} from '../test-utils/mock-data'
import {enterpriseOwnedOrgRole} from '../test-utils/org-mock-data'
import {NewRoleAssignmentListItem} from '../components/NewRoleAssignmentListItem'
import {ActionList} from '@primer/react'

test('Renders RoleAssignmentList', () => {
  const props = getNewRoleAssignmentListItemProps(false)
  // list item needs to be within a list to be valid to render
  render(
    <div>
      <ActionList selectionVariant="single">
        <NewRoleAssignmentListItem {...props} />
      </ActionList>
    </div>,
  )

  const item = screen.getByTestId(`role-assignment-list-item-${props.role.name}`)
  expect(item).toBeInTheDocument()
  const roleIcon = screen.getByTestId('role-icon') // technically the span around the icon
  expect(roleIcon).toBeInTheDocument()
  expect(roleIcon.childNodes[0]).toHaveClass(`octicon-${props.role.icon}`)
  const roleName = screen.getByText(props.role.name)
  expect(roleName).toBeInTheDocument()
  const roleDescription = screen.getByText(props.role.description!)
  expect(roleDescription).toBeInTheDocument()
  const infoIcon = screen.getByTestId('info-icon') // technically the span around the icon
  expect(infoIcon).toBeInTheDocument()
  expect(infoIcon.childNodes[0]).toHaveClass('octicon-info')
})

test.each([true, false])('Role assignment is indicated by presence of checkmark', (selected: boolean) => {
  const assignedProps = getNewRoleAssignmentListItemProps(selected)
  // list item needs to be within a list to be valid to render
  render(
    <div>
      <ActionList selectionVariant="single">
        <NewRoleAssignmentListItem {...assignedProps} />
      </ActionList>
    </div>,
  )

  const item = screen.getByTestId(`role-assignment-list-item-${assignedProps.role.name}`)
  expect(item).toBeInTheDocument()
  const checkboxContainer = item.childNodes[0]

  if (selected) {
    // eslint-disable-next-line jest/no-conditional-expect
    expect(checkboxContainer!.childNodes[0]).toHaveClass('octicon-check') // assert selected
  } else {
    // eslint-disable-next-line jest/no-conditional-expect
    expect(checkboxContainer!.hasChildNodes()).toBeFalsy() // assert not selected
  }
})

test('enterprise-owned org role includes enterprise information', () => {
  const props = getNewRoleAssignmentListItemProps(false, enterpriseOwnedOrgRole)
  // list item needs to be within a list to be valid to render
  render(
    <div>
      <ActionList selectionVariant="single">
        <NewRoleAssignmentListItem {...props} />
      </ActionList>
    </div>,
  )

  const span = screen.getByTestId('enterprise-owned-role')
  expect(span).toBeInTheDocument()
  expect(span).toHaveTextContent(`Role managed by ${props.role.enterpriseOwner!.name}`)
})

test('clicking role calls callback prop w/ id', async () => {
  const props = getNewRoleAssignmentListItemProps(false)
  // list item needs to be within a list to be valid to render
  const {user} = render(
    <div>
      <ActionList selectionVariant="single">
        <NewRoleAssignmentListItem {...props} />
      </ActionList>
    </div>,
  )

  const role = screen.getByRole('menuitemradio')
  expect(role).toBeInTheDocument()

  await user.click(role)
  expect(props.onSelectCallback).toHaveBeenCalledWith(props.role.id)
})

test('clicking role info opens FGP dialog', async () => {
  const props = getNewRoleAssignmentListItemProps(false)
  // list item needs to be within a list to be valid to render
  const {user} = render(
    <div>
      <ActionList selectionVariant="single">
        <NewRoleAssignmentListItem {...props} />
      </ActionList>
    </div>,
  )

  const role = screen.getByRole('menuitemradio')
  expect(role).toBeInTheDocument()
  const infoIcon = screen.getByTestId('info-icon')
  expect(infoIcon).toBeInTheDocument()

  await user.click(infoIcon)
  const fgpDialog = screen.getByRole('dialog')
  expect(fgpDialog).toBeInTheDocument()
})
