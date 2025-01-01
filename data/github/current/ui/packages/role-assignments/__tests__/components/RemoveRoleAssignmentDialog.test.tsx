import {render} from '@github-ui/react-core/test-utils'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {screen} from '@testing-library/react'
import {RemoveRoleAssignmentDialog} from '../../components/RemoveRoleAssignmentDialog'
import {getRoleDetailsRowRemoveDialogProps} from '../../test-utils/mock-data'

const showBannerMock = jest.fn()
const navigateMock = jest.fn()

jest.mock('@github-ui/role-assignments/banner-provider', () => ({
  useBannerContext: jest.fn(() => {
    return {navigate: navigateMock, showBanner: showBannerMock}
  }),
}))

const destroyRoleAssignmentPathMock = jest.fn(
  (params: {actorId: number; actorType: string; roleId: number}) =>
    `/role-assignments/${params.actorType}/${params.actorId}/${params.roleId}`,
)
jest.mock('@github-ui/role-assignments/routing-provider', () => ({
  useRoutingContext: () => {
    return {
      destroyRoleAssignmentPath: destroyRoleAssignmentPathMock,
    }
  },
}))

// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

const mockVerifiedFetch = verifiedFetchJSON as jest.Mock

interface MockResponseOptions {
  response?: {
    success: boolean
    message?: string
    error?: string
  }
  status?: number
}
// Helper to set the response - can be called at the beginning of each test
const mockFetchResponse = (options: MockResponseOptions = {}) => {
  const {response = {success: true}, status = 200} = options

  mockVerifiedFetch.mockImplementation((_path, _init) =>
    Promise.resolve({
      ok: status >= 200 && status < 300,
      status,
      json: () => Promise.resolve(response),
    }),
  )
}

beforeEach(() => {
  jest.clearAllMocks()
  Object.defineProperty(window, 'location', {
    writable: true,
    value: {search: ''},
  })
})

test('Renders text, cancel, remove', () => {
  const props = getRoleDetailsRowRemoveDialogProps()
  render(<RemoveRoleAssignmentDialog {...props} />)

  expect(screen.getByText('about to remove the direct assignment', {exact: false})).toBeInTheDocument()
  expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
  expect(screen.getByRole('button', {name: 'Remove'})).toBeInTheDocument()
})

test('Cancel button closes modal without submitting', async () => {
  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RemoveRoleAssignmentDialog {...props} />)

  const cancel = screen.queryByRole('button', {name: 'Cancel'})
  expect(cancel).toBeInTheDocument()
  await user.click(cancel!)

  expect(props.setOpen).toHaveBeenCalledWith(false)
})

test('Removing button from non-default page submits and reloads default page with banner', async () => {
  Object.defineProperty(window, 'location', {
    writable: true,
    value: {search: '?page=2'},
  })

  mockFetchResponse({
    response: {
      success: true,
      message: 'Success message',
    },
  })

  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RemoveRoleAssignmentDialog {...props} />)

  const remove = screen.queryByRole('button', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
  await user.click(remove!)

  expect(mockVerifiedFetch).toHaveBeenCalledWith(
    destroyRoleAssignmentPathMock({actorId: props.actor.id, actorType: props.actor.type, roleId: props.roleId}),
    {method: 'DELETE'},
  )
  expect(navigateMock).toHaveBeenCalledWith(
    `${window.location.pathname}`,
    {replace: true},
    {
      message: 'Success message',
      variant: 'success',
    },
  )
})

test('Removing button from non-default page submits and reloads default page with persisting query', async () => {
  Object.defineProperty(window, 'location', {
    writable: true,
    value: {search: '?query=mona&page=2'},
  })

  mockFetchResponse({
    response: {
      success: true,
      message: 'Success message',
    },
  })

  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RemoveRoleAssignmentDialog {...props} />)

  const remove = screen.queryByRole('button', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
  await user.click(remove!)

  expect(mockVerifiedFetch).toHaveBeenCalledWith(
    destroyRoleAssignmentPathMock({actorId: props.actor.id, actorType: props.actor.type, roleId: props.roleId}),
    {method: 'DELETE'},
  )
  expect(navigateMock).toHaveBeenCalledWith(
    `${window.location.pathname}?query=mona`,
    {replace: true},
    {
      message: 'Success message',
      variant: 'success',
    },
  )
})

test('Removing button from triple-digit page submits and reloads default page with persisting query', async () => {
  Object.defineProperty(window, 'location', {
    writable: true,
    value: {search: '?query=mona&page=123'},
  })

  mockFetchResponse({
    response: {
      success: true,
      message: 'Success message',
    },
  })

  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RemoveRoleAssignmentDialog {...props} />)

  const remove = screen.queryByRole('button', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
  await user.click(remove!)

  expect(mockVerifiedFetch).toHaveBeenCalledWith(
    destroyRoleAssignmentPathMock({actorId: props.actor.id, actorType: props.actor.type, roleId: props.roleId}),
    {method: 'DELETE'},
  )
  expect(navigateMock).toHaveBeenCalledWith(
    `${window.location.pathname}?query=mona`,
    {replace: true},
    {
      message: 'Success message',
      variant: 'success',
    },
  )
})

test('Remove button submits and reloads page with banner', async () => {
  mockFetchResponse({
    response: {
      success: true,
      message: 'Success message',
    },
  })

  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RemoveRoleAssignmentDialog {...props} />)

  const remove = screen.queryByRole('button', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
  await user.click(remove!)

  expect(mockVerifiedFetch).toHaveBeenCalledWith(
    destroyRoleAssignmentPathMock({actorId: props.actor.id, actorType: props.actor.type, roleId: props.roleId}),
    {method: 'DELETE'},
  )
  expect(navigateMock).toHaveBeenCalledWith(
    `${window.location.pathname}`,
    {replace: true},
    {
      message: 'Success message',
      variant: 'success',
    },
  )
})

test('Remove failure shows banner with server message when status is 422', async () => {
  mockFetchResponse({response: {success: false, error: 'error message'}, status: 422})

  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RemoveRoleAssignmentDialog {...props} />)

  const remove = screen.queryByRole('button', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
  await user.click(remove!)

  expect(mockVerifiedFetch).toHaveBeenCalledWith(
    destroyRoleAssignmentPathMock({actorId: props.actor.id, actorType: props.actor.type, roleId: props.roleId}),
    {method: 'DELETE'},
  )
  expect(showBannerMock).toHaveBeenCalled()
  expect(showBannerMock).toHaveBeenCalledWith({
    message: 'error message',
    variant: 'critical',
  })
})

test('Remove failure shows banner with server message when status is 403', async () => {
  mockFetchResponse({response: {success: false, error: 'error message'}, status: 403})

  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RemoveRoleAssignmentDialog {...props} />)

  const remove = screen.queryByRole('button', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
  await user.click(remove!)

  expect(mockVerifiedFetch).toHaveBeenCalledWith(
    destroyRoleAssignmentPathMock({actorId: props.actor.id, actorType: props.actor.type, roleId: props.roleId}),
    {method: 'DELETE'},
  )
  expect(showBannerMock).toHaveBeenCalled()
  expect(showBannerMock).toHaveBeenCalledWith({
    message: 'error message',
    variant: 'critical',
  })
})

test('Remove failure shows generic error message', async () => {
  mockFetchResponse({status: 500})

  const props = getRoleDetailsRowRemoveDialogProps()
  const {user} = render(<RemoveRoleAssignmentDialog {...props} />)

  const remove = screen.queryByRole('button', {name: 'Remove'})
  expect(remove).toBeInTheDocument()
  await user.click(remove!)

  expect(mockVerifiedFetch).toHaveBeenCalledWith(
    destroyRoleAssignmentPathMock({actorId: props.actor.id, actorType: props.actor.type, roleId: props.roleId}),
    {method: 'DELETE'},
  )
  expect(showBannerMock).toHaveBeenCalled()
  expect(showBannerMock).toHaveBeenCalledWith({
    message: 'Something went wrong while removing the role assignment. Please try again later.',
    variant: 'critical',
  })
})

test('Renders copy about inherited roles if role is inherited from one source', async () => {
  const props = getRoleDetailsRowRemoveDialogProps()
  const indirect_assignments = [
    {
      team_name: 'Team 1',
      team_url: '/team_1_url',
      type: 'BusinessTeam',
    },
  ]

  render(<RemoveRoleAssignmentDialog {...props} indirectAssignments={indirect_assignments} />)

  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()
  expect(dialog).toHaveTextContent(
    `You're about to remove the direct assignment of the ${props.roleName} role from the ${props.actor.name} enterprise team.`,
  )
  expect(dialog).toHaveTextContent(
    `However, this role will still be assigned through the ${indirect_assignments[0]!.team_name} team.`,
  )
})

test('Renders copy about inherited roles if role is inherited from two sources', async () => {
  const props = getRoleDetailsRowRemoveDialogProps()
  const indirect_assignments = [
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
  ]

  render(<RemoveRoleAssignmentDialog {...props} indirectAssignments={indirect_assignments} />)

  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()
  expect(dialog).toHaveTextContent(
    `You're about to remove the direct assignment of the ${props.roleName} role from the ${props.actor.name} enterprise team.`,
  )
  expect(dialog).toHaveTextContent(
    `However, this role will still be assigned through the ${indirect_assignments[0]!.team_name} and ${
      indirect_assignments[1]!.team_name
    } teams.`,
  )
})

test('Renders copy about inherited roles if role is inherited from three sources', async () => {
  const props = getRoleDetailsRowRemoveDialogProps()
  const indirect_assignments = [
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
  ]

  render(<RemoveRoleAssignmentDialog {...props} indirectAssignments={indirect_assignments} />)

  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()
  expect(dialog).toHaveTextContent(
    `You're about to remove the direct assignment of the ${props.roleName} role from the ${props.actor.name} enterprise team.`,
  )
  expect(dialog).toHaveTextContent(
    `However, this role will still be assigned through the ${indirect_assignments[0]!.team_name}, ${
      indirect_assignments[1]!.team_name
    }, and ${indirect_assignments[2]!.team_name} teams.`,
  )
})
