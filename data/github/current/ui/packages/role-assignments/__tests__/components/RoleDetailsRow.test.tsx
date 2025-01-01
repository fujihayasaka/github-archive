import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {RoleDetailsRow} from '../../components/RoleDetailsRow'
import {getRoleDetailsRowProps} from '../../test-utils/mock-data'
import {BannerProvider} from '../../BannerProvider'

const BannerProviderWrapper = ({children}: {children: React.ReactNode}) => <BannerProvider>{children}</BannerProvider>

test('Renders icon, title, description, trailing menu for given role', () => {
  const props = getRoleDetailsRowProps()
  render(<RoleDetailsRow {...props} />, {wrapper: BannerProviderWrapper})

  const roleIcon = screen.getByTestId('role-icon')
  expect(roleIcon.childNodes[0]).toHaveClass(`octicon-${props.role.octicon}`)
  expect(screen.getByText(props.role.name)).toBeInTheDocument()
  expect(screen.getByText(props.role.description)).toBeInTheDocument()
  expect(screen.getByRole('button', {name: `Actions for ${props.role.name}`})).toBeInTheDocument()
})

test('ActionMenu contents render as expected', async () => {
  const props = getRoleDetailsRowProps()
  const {user} = render(<RoleDetailsRow {...props} />, {wrapper: BannerProviderWrapper})

  const actionMenu = screen.queryByTestId('role-action-menu')
  expect(actionMenu).toBeInTheDocument()

  await user.click(actionMenu!)

  const details = screen.getByRole('menuitem', {name: 'Details'})
  expect(details).toBeInTheDocument()
  const remove = screen.getByRole('menuitem', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
})

test('ActionMenu details option opens dialog', async () => {
  const props = getRoleDetailsRowProps()
  const {user} = render(<RoleDetailsRow {...props} />, {wrapper: BannerProviderWrapper})

  const actionMenu = screen.queryByTestId('role-action-menu')
  expect(actionMenu).toBeInTheDocument()

  await user.click(actionMenu!)

  const details = screen.queryByRole('menuitem', {name: 'Details'})
  await user.click(details!)

  expect(screen.getByRole('dialog')).toBeInTheDocument()
  expect(screen.getByText('Enterprise')).toBeInTheDocument()
  expect(screen.getByText('category1')).toBeInTheDocument()
  expect(screen.getByText('permissionA')).toBeInTheDocument()
  expect(screen.getByText('Organization')).toBeInTheDocument()
  expect(screen.getByText('category2')).toBeInTheDocument()
  expect(screen.getByText('permissionB')).toBeInTheDocument()
})

test('ActionMenu remove option opens confirmation dialog', async () => {
  const props = getRoleDetailsRowProps()
  const {user} = render(<RoleDetailsRow {...props} />, {wrapper: BannerProviderWrapper})

  await user.click(screen.getByRole('button')) // open selectpanel menu
  await user.click(screen.getByRole('menuitem', {name: 'Remove'})) // open confirmation dialog

  expect(screen.getByRole('dialog')).toBeInTheDocument()
  expect(screen.getByText('about to remove the assignment', {exact: false})).toBeInTheDocument()
  expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
  expect(screen.getByRole('button', {name: 'Remove'})).toBeInTheDocument()
})

test('Remove action gated behind write permission', async () => {
  const props = getRoleDetailsRowProps()
  props.viewerPermissions.write = false
  const {user} = render(<RoleDetailsRow {...props} />, {wrapper: BannerProviderWrapper})

  const actionMenu = screen.queryByTestId('role-action-menu')
  expect(actionMenu).toBeInTheDocument()

  await user.click(actionMenu!)

  expect(screen.queryByRole('menuitem', {name: 'Remove'})).not.toBeInTheDocument()
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
})
