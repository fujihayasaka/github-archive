import {render} from '@github-ui/react-core/test-utils'
import {verifiedFetch} from '@github-ui/verified-fetch'
import {screen, within} from '@testing-library/react'
import {RemoveRoleAssignmentButton} from '../../components/RemoveRoleAssignmentButton'
import {ActorType, type RoleAssignment} from '../../types/ActorRoleAssignment'

const showBannerMock = jest.fn()
const navigateMock = jest.fn()

jest.mock('../../BannerProvider', () => ({
  useBannerContext: jest.fn(() => {
    return {navigate: navigateMock, showBanner: showBannerMock}
  }),
}))

const mockVerifiedFetch = verifiedFetch as jest.Mock
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetch: jest.fn(),
}))

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

const path = '/role-assignments'
beforeAll(() => {
  jest.spyOn(window, 'location', 'get').mockReturnValue({
    ...window.location,
    pathname: path,
  })
})

beforeEach(() => {
  navigateMock.mockClear()
})

test('Renders RemoveAssignmentButton', async () => {
  const {user} = render(<RemoveRoleAssignmentButton actor={actor} roleAssignment={directRoleAssignment} />)

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

test('Renders copy about inherited roles if role is inherited from one source', async () => {
  const roleAssignment = {
    ...directRoleAssignment,
    indirect_assignments: [
      {
        team_name: 'Team 1',
        team_url: '/team_1_url',
        type: 'BusinessTeam',
      },
    ],
  }

  await openDialog(roleAssignment)
  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()
  expect(dialog).toHaveTextContent(
    `You're about to remove the direct assignment of the ${directRoleAssignment.role.name} role from ${actor.name}.`,
  )
  expect(dialog).toHaveTextContent(
    `However, this role will still be assigned through the ${roleAssignment.indirect_assignments[0]!.team_name} team.`,
  )
})

test('Renders copy about inherited roles if role is inherited from two sources', async () => {
  const roleAssignment = {
    ...directRoleAssignment,
    indirect_assignments: [
      {
        team_name: 'Team 1',
        team_url: '/team_1_url',
        type: 'BusinessTeam',
      },
      {
        team_name: 'Team 2',
        team_url: '/team_2_url',
        type: 'BusinessTeam',
      },
    ],
  }

  await openDialog(roleAssignment)
  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()
  expect(dialog).toHaveTextContent(
    `You're about to remove the direct assignment of the ${directRoleAssignment.role.name} role from ${actor.name}.`,
  )
  expect(dialog).toHaveTextContent(
    `However, this role will still be assigned through the ${roleAssignment.indirect_assignments[0]!.team_name} and ${
      roleAssignment.indirect_assignments[1]!.team_name
    } teams.`,
  )
})

test('Renders copy about inherited roles if role is inherited from three sources', async () => {
  const roleAssignment = {
    ...directRoleAssignment,
    indirect_assignments: [
      {
        team_name: 'Team 1',
        team_url: '/team_1_url',
        type: 'BusinessTeam',
      },
      {
        team_name: 'Team 2',
        team_url: '/team_2_url',
        type: 'BusinessTeam',
      },
      {
        team_name: 'Team 3',
        team_url: '/team_3_url',
        type: 'BusinessTeam',
      },
    ],
  }

  await openDialog(roleAssignment)
  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()
  expect(dialog).toHaveTextContent(
    `You're about to remove the direct assignment of the ${directRoleAssignment.role.name} role from ${actor.name}.`,
  )
  expect(dialog).toHaveTextContent(
    `However, this role will still be assigned through the ${roleAssignment.indirect_assignments[0]!.team_name}, ${
      roleAssignment.indirect_assignments[1]!.team_name
    }, and ${roleAssignment.indirect_assignments[2]!.team_name} teams.`,
  )
})

test('Removes role assignment successfully assigns a banner and reloads the page', async () => {
  // mock server response
  const bannerMessage = `The ${directRoleAssignment.role.name} role was successfully removed from ${actor.name}.`
  mockVerifiedFetch.mockResolvedValue({
    ok: true,
    json: async () => {
      return {
        success: true,
        message: bannerMessage,
      }
    },
  })

  await clickRemoveButton()

  // navigate with banner
  expect(navigateMock).toHaveBeenCalledWith(path, {replace: true}, {message: bannerMessage, variant: 'success'})
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
})

test('Removes role assignment unsuccessfully assigns a banner and closes the dialog', async () => {
  // mock server response
  mockVerifiedFetch.mockResolvedValue({
    ok: true,
    json: async () => {
      return {
        success: false,
      }
    },
  })

  await clickRemoveButton()

  // banner is shown
  expect(showBannerMock).toHaveBeenCalledWith({
    message: 'Something went wrong while removing the role assignment. Please try again later.',
    variant: 'critical',
  })
  expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
})

async function openDialog(roleAssignment: RoleAssignment = directRoleAssignment) {
  const {user} = render(<RemoveRoleAssignmentButton actor={actor} roleAssignment={roleAssignment} />)

  const button = screen.getByRole('button', {name: 'Remove role assignment'})
  expect(button).toBeInTheDocument()

  // click button to open dialog
  await user.click(button)

  return user
}

async function clickRemoveButton(roleAssignment: RoleAssignment = directRoleAssignment) {
  const user = await openDialog(roleAssignment)

  // click remove button
  const removeButton = within(screen.getByRole('dialog')).getByRole('button', {name: 'Remove'})
  expect(removeButton).toBeInTheDocument()
  await user.click(removeButton)
}
