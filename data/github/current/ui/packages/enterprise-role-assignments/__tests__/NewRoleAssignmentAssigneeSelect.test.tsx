import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'
import {getNewRoleAssignmentAssigneeSelectProps, mockAssigneeQueryResponse} from '../test-utils/mock-data'
import {getNewOrgRoleAssignmentAssigneeSelectProps, mockOrgAssigneeQueryResponse} from '../test-utils/org-mock-data'
import {NewRoleAssignmentAssigneeSelect} from '../components/NewRoleAssignmentAssigneeSelect'

test('Renders RoleAssignmentList', async () => {
  const props = getNewRoleAssignmentAssigneeSelectProps()
  const {user} = render(<NewRoleAssignmentAssigneeSelect {...props} />)

  const assigneeButton = screen.getByRole('button', {name: 'Select user or team'})
  expect(assigneeButton).toBeInTheDocument()
  await user.click(assigneeButton)

  await mockAssigneeQueryResponse(
    [
      {id: 1, name: 'monalisa', secondaryName: 'Octocat', type: 'user', avatarUrl: 'test.com/mona'},
      {id: 2, name: 'mallardlisa', secondaryName: 'Octoduck', type: 'user', avatarUrl: 'test.com/mallard'},
      {id: 3, name: 'doggolisa', secondaryName: 'Octodog', type: 'user', avatarUrl: 'test.com/doggo'},
      {id: 4, name: 'brianbat', secondaryName: 'batty', type: 'user', avatarUrl: 'test.com/brian'},
      {id: 5, name: 'justhoward', secondaryName: 'howard', type: 'user', avatarUrl: 'test.com/howard'},
      {id: 6, name: 'chickenlittle', secondaryName: 'little', type: 'user', avatarUrl: 'test.com/little'},
    ],
    [
      {id: 7, name: 'team 1', secondaryName: null, type: 'businessteam', avatarUrl: 'test.com/team1'},
      {id: 8, name: 'team 2', secondaryName: null, type: 'businessteam', avatarUrl: 'test.com/team2'},
    ],
  )

  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()

  const searchInput = screen.getByRole('textbox')
  expect(searchInput).toBeInTheDocument()

  await waitFor(() => {
    const userItem = screen.getByRole('option', {name: 'monalisa'})
    expect(userItem).toBeInTheDocument()
  })

  await waitFor(() => {
    const userDescription = screen.getByText('Octocat')
    expect(userDescription).toBeInTheDocument()
  })

  await waitFor(() => {
    const teamItem = screen.getByRole('option', {name: 'team 1'})
    expect(teamItem).toBeInTheDocument()
  })

  await waitFor(() => {
    const userHeader = screen.getByText('Users 5 of 6')
    expect(userHeader).toBeInTheDocument()
  })

  await waitFor(() => {
    const teamHeader = screen.getByText('Enterprise teams 2 of 2')
    expect(teamHeader).toBeInTheDocument()
  })
})

test('Returns no headers when query is empty', async () => {
  const props = getNewRoleAssignmentAssigneeSelectProps()
  const {user} = render(<NewRoleAssignmentAssigneeSelect {...props} />)

  const assigneeButton = screen.getByRole('button', {name: 'Select user or team'})
  expect(assigneeButton).toBeInTheDocument()
  await user.click(assigneeButton)

  await mockAssigneeQueryResponse()

  const dialog = screen.getByRole('dialog')
  expect(dialog).toBeInTheDocument()

  const searchInput = screen.getByRole('textbox')
  expect(searchInput).toBeInTheDocument()

  await waitFor(() => {
    const userHeader = screen.queryByText(/Users/)
    expect(userHeader).not.toBeInTheDocument()
  })

  await waitFor(() => {
    const teamHeader = screen.queryByText(/Enterprise teams/)
    expect(teamHeader).not.toBeInTheDocument()
  })
})

test('select team items have trailing text for org view', async () => {
  const props = getNewOrgRoleAssignmentAssigneeSelectProps()
  const {user} = render(<NewRoleAssignmentAssigneeSelect {...props} />)

  const assigneeButton = screen.getByRole('button', {name: 'Select user or team'})
  expect(assigneeButton).toBeInTheDocument()
  await user.click(assigneeButton)

  await mockOrgAssigneeQueryResponse(
    [{id: 1, name: 'monalisa', secondaryName: 'Octocat', type: 'user', avatarUrl: 'test.com/mona'}],
    [
      {id: 2, name: 'team 1', secondaryName: null, type: 'businessteam', avatarUrl: 'test.com/team1'},
      {id: 3, name: 'team 2', secondaryName: null, type: 'team', avatarUrl: 'test.com/team2'},
    ],
  )

  await waitFor(() => {
    const teamItem = screen.getByRole('option', {name: 'team 1'})
    expect(teamItem).toBeInTheDocument()
  })

  await waitFor(() => {
    const trailingText = screen.getByText('Enterprise team')
    expect(trailingText).toBeInTheDocument()
  })

  await waitFor(() => {
    const teamItem = screen.getByRole('option', {name: 'team 2'})
    expect(teamItem).toBeInTheDocument()
  })

  await waitFor(() => {
    const trailingText = screen.getByText('Org team')
    expect(trailingText).toBeInTheDocument()
  })
})

test('select team items have no trailing text for enterprise view', async () => {
  const props = getNewRoleAssignmentAssigneeSelectProps()
  const {user} = render(<NewRoleAssignmentAssigneeSelect {...props} />)

  const assigneeButton = screen.getByRole('button', {name: 'Select user or team'})
  expect(assigneeButton).toBeInTheDocument()
  await user.click(assigneeButton)

  await mockAssigneeQueryResponse(
    [{id: 1, name: 'monalisa', secondaryName: 'Octocat', type: 'user', avatarUrl: 'test.com/mona'}],
    [{id: 2, name: 'team 1', secondaryName: null, type: 'businessteam', avatarUrl: 'test.com/team1'}],
  )

  await waitFor(() => {
    const teamItem = screen.getByRole('option', {name: 'team 1'})
    expect(teamItem).toBeInTheDocument()
  })

  await waitFor(() => {
    expect(screen.queryByText('Enterprise team')).not.toBeInTheDocument()
  })
})
