import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {RemoveRoleAssignmentButton} from '../../components/RemoveRoleAssignmentButton'
import {ActorType} from '../../types/ActorRoleAssignment'
import {BannerProvider} from '../../BannerProvider'
import {RoutingProvider} from '../../contexts/RoutingProvider'

const actor = {
  id: 1,
  name: 'MonaLisa',
  description: 'monalisa',
  avatar_url: '/monalisa.png',
  type: ActorType.User,
}

const directRoleAssignment = {
  role: {
    id: 2,
    name: 'Role Name',
    description: 'role description',
    octicon: 'note',
  },
  directly_assigned: true,
  indirect_assignments: [],
}

const ProviderWrapper = ({children}: {children: React.ReactNode}) => (
  <RoutingProvider slug="slug" ownerType="enterprise">
    <BannerProvider>{children}</BannerProvider>
  </RoutingProvider>
)

test('Renders RemoveAssignmentButton', async () => {
  const {user} = render(
    <RemoveRoleAssignmentButton actor={actor} roleAssignment={directRoleAssignment} canViewEnterpriseTeams />,
    {
      wrapper: ProviderWrapper,
    },
  )

  const button = screen.getByRole('button', {name: 'Remove role assignment'})
  expect(button).toBeInTheDocument()

  // no dialog before button click
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()

  // click button to open dialog
  await user.click(button)
  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()
  expect(dialog).toHaveTextContent('Remove role assignment')
  expect(dialog).toHaveTextContent(
    `You're about to remove the direct assignment of the ${directRoleAssignment.role.name} role from ${actor.name}.`,
  )
  const cancelButton = within(dialog).getByRole('button', {name: 'Cancel'})
  expect(cancelButton).toBeInTheDocument()
  expect(within(dialog).getByRole('button', {name: 'Remove'})).toBeInTheDocument()

  const removeButton = within(dialog).getByRole('button', {name: 'Remove'})
  expect(removeButton).toBeInTheDocument()

  // cancel dismisses dialog
  await user.click(cancelButton)
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
})
