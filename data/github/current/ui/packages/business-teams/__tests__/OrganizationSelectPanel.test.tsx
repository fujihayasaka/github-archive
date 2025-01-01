import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {getOrganizationSelectPanelProps, getOrganizationSuggestionsPayload} from '../test-utils/mock-data'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'
import {OrganizationSelectPanel} from '../helpers/OrganizationSelectPanel'

jest.useFakeTimers()

const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

beforeEach(() => {
  mockVerifiedFetchJSON.mockReset()
})

test('Renders org suggestions then close without adding', async () => {
  const props = getOrganizationSelectPanelProps()
  const {user} = render(<OrganizationSelectPanel {...props} />)
  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  expect(selectOrgsButton).toBeInTheDocument()

  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })

  expect(screen.queryByTestId('org-1')).not.toBeInTheDocument()
  expect(screen.queryByTestId('org-2')).not.toBeInTheDocument()

  await user.click(selectOrgsButton)

  let org1 = screen.getByTestId('org-1')
  expect(org1).toBeInTheDocument()
  expect(org1).toBeEnabled()
  expect(org1).toHaveTextContent('A first org')

  expect(org1).toHaveAttribute('aria-selected', 'false')
  await user.click(org1)
  expect(org1).toHaveAttribute('aria-selected', 'true')

  const org2 = screen.getByTestId('org-2')
  expect(org2).toBeInTheDocument()
  expect(org2).toBeEnabled()
  expect(org2).toHaveTextContent('The other org')

  const org3 = screen.getByTestId('org-3')
  expect(org3).toBeInTheDocument()
  expect(org3).toBeEnabled()
  expect(org3).toHaveTextContent('The third org')

  const cancelButton = screen.getByRole('button', {name: 'Cancel'})
  await user.click(cancelButton)

  expect(screen.queryByTestId('org-1')).not.toBeInTheDocument()
  expect(screen.queryByTestId('org-2')).not.toBeInTheDocument()

  expect(props.onOrganizationsAdded).not.toHaveBeenCalled()

  await user.click(selectOrgsButton)
  org1 = screen.getByTestId('org-1')
  expect(org1).toBeInTheDocument()
  expect(org1).toHaveAttribute('aria-selected', 'false')

  const addOrgsButton = screen.getByTestId('add-orgs')
  expect(addOrgsButton).toHaveTextContent('Add 0')
  expect(addOrgsButton).toBeDisabled()
})

test('Add organizations', async () => {
  const props = getOrganizationSelectPanelProps()
  const {user} = render(<OrganizationSelectPanel {...props} />)

  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  expect(selectOrgsButton).toBeInTheDocument()
  await user.click(selectOrgsButton)

  const org1 = screen.getByTestId('org-1')
  expect(org1).toBeInTheDocument()
  expect(org1).toHaveAttribute('aria-selected', 'false')
  await user.click(org1)
  expect(org1).toHaveAttribute('aria-selected', 'true')

  const org3 = screen.getByTestId('org-3')
  expect(org3).toBeInTheDocument()
  expect(org3).toHaveAttribute('aria-selected', 'false')
  await user.click(org3)
  expect(org3).toHaveAttribute('aria-selected', 'true')

  const addOrgsButton = screen.getByTestId('add-orgs')
  expect(addOrgsButton).toHaveTextContent('Add 2')
  await user.click(addOrgsButton)

  const orgs = getOrganizationSuggestionsPayload().organizations
  expect(props.onOrganizationsAdded).toHaveBeenCalledWith([orgs[0], orgs[2]])
})

test('Search organizations when the team is being created', async () => {
  const props = getOrganizationSelectPanelProps()
  const {user} = render(<OrganizationSelectPanel {...props} />)

  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  await user.click(selectOrgsButton)

  const searchInput = screen.getByTestId('org-search-input')
  await user.type(searchInput, 'other')
  act(jest.runOnlyPendingTimers)

  const org2 = await screen.findByTestId('org-2')
  expect(org2).toBeInTheDocument()

  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/enterprises/acme-corp/organization_suggestions`, {
    method: 'POST',
    body: {query: 'other', selectedOrganizationIds: []},
    headers: {Accept: 'application/json'},
  })
})

test('Search organizations when the team is already created', async () => {
  const props = getOrganizationSelectPanelProps()
  const {user} = render(<OrganizationSelectPanel {...props} teamSlug="acme-engineering" />)

  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  await user.click(selectOrgsButton)

  const searchInput = screen.getByTestId('org-search-input')
  await user.type(searchInput, 'other')
  act(jest.runOnlyPendingTimers)

  const org2 = await screen.findByTestId('org-2')
  expect(org2).toBeInTheDocument()

  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(
    `/enterprises/acme-corp/teams/acme-engineering/organization_suggestions?query=other`,
    {
      method: 'GET',
      headers: {Accept: 'application/json'},
    },
  )
})

test('Searching for a nonexistent org displays an error', async () => {
  const props = getOrganizationSelectPanelProps()
  const {user} = render(<OrganizationSelectPanel {...props} />)

  mockVerifiedFetchJSON
    .mockResolvedValueOnce({
      json: async () => getOrganizationSuggestionsPayload(),
      ok: true,
    })
    .mockResolvedValue({
      json: async () => ({organizations: [], totalAvailbleCount: 6}),
      ok: true,
    })

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  await user.click(selectOrgsButton)

  const searchInput = screen.getByTestId('org-search-input')
  await user.type(searchInput, 'nonExistant')
  act(jest.runOnlyPendingTimers)

  const noOrgsFound = await screen.findByTestId('no-orgs-found-text')
  expect(noOrgsFound).toBeInTheDocument()

  expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(2)
  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/enterprises/acme-corp/organization_suggestions`, {
    method: 'POST',
    body: {query: '', selectedOrganizationIds: []},
    headers: {Accept: 'application/json'},
  })
  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/enterprises/acme-corp/organization_suggestions`, {
    method: 'POST',
    body: {query: 'nonExistant', selectedOrganizationIds: []},
    headers: {Accept: 'application/json'},
  })
})

test('Displays no more org available after selecting all', async () => {
  const props = {
    ...getOrganizationSelectPanelProps(),
    initialSelectedIds: [1, 2, 3],
  }
  const {user} = render(<OrganizationSelectPanel {...props} />)

  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => ({organizations: [], totalAvailableCount: 0}),
    ok: true,
  })

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  await user.click(selectOrgsButton)

  const noOrgsFound = screen.getByTestId('no-orgs-remaining-text')
  expect(noOrgsFound).toBeInTheDocument()

  expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(1)
  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/enterprises/acme-corp/organization_suggestions`, {
    method: 'POST',
    body: {query: '', selectedOrganizationIds: [1, 2, 3]},
    headers: {Accept: 'application/json'},
  })
})

test('Selection is maintained when searching different results', async () => {
  const props = getOrganizationSelectPanelProps()
  const {user} = render(<OrganizationSelectPanel {...props} />)

  mockVerifiedFetchJSON.mockResolvedValueOnce({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })

  const selectOrgsButton = screen.getByTestId('select-orgs-button')
  await user.click(selectOrgsButton)

  const org1 = screen.getByTestId('org-1')
  await user.click(org1)

  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => ({
      ...getOrganizationSuggestionsPayload(),
      organizations: [getOrganizationSuggestionsPayload().organizations[1]],
    }),
    ok: true,
  })

  const searchInput = screen.getByTestId('org-search-input')
  await user.type(searchInput, 'other')
  act(jest.runOnlyPendingTimers)

  const org2 = await screen.findByTestId('org-2')
  await user.click(org2)

  expect(screen.queryByTestId('org-1')).not.toBeInTheDocument()

  const addOrgsButton = screen.getByTestId('add-orgs')
  expect(addOrgsButton).toHaveTextContent('Add 2')
  await user.click(addOrgsButton)

  const orgs = getOrganizationSuggestionsPayload().organizations
  expect(props.onOrganizationsAdded).toHaveBeenCalledWith([orgs[0], orgs[1]])

  expect(mockVerifiedFetchJSON).toHaveBeenCalledTimes(2)
  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/enterprises/acme-corp/organization_suggestions`, {
    method: 'POST',
    body: {query: '', selectedOrganizationIds: []},
    headers: {Accept: 'application/json'},
  })
  expect(mockVerifiedFetchJSON).toHaveBeenCalledWith(`/enterprises/acme-corp/organization_suggestions`, {
    method: 'POST',
    body: {query: 'other', selectedOrganizationIds: []},
    headers: {Accept: 'application/json'},
  })
})

test('Handles org limit', async () => {
  const props = {
    ...getOrganizationSelectPanelProps(),
    enterpriseTeamsOrgAssignmentLimit: 1,
  }
  const {user} = render(<OrganizationSelectPanel {...props} />)

  mockVerifiedFetchJSON.mockResolvedValue({
    json: async () => getOrganizationSuggestionsPayload(),
    ok: true,
  })

  await user.click(screen.getByTestId('select-orgs-button'))

  expect(screen.queryByTestId('org-assignments-limit-error')).not.toBeInTheDocument()

  const org1 = screen.getByTestId('org-1')
  await user.click(org1)
  const limit = screen.getByTestId('org-assignments-limit-error')
  expect(limit).toBeVisible()
  expect(limit).toHaveTextContent('1-organization limit reached. Please remove some organizations before adding more.')

  await user.click(org1)
  expect(screen.queryByTestId('org-assignments-limit-error')).not.toBeInTheDocument()

  await user.click(org1)

  const org2 = screen.getByTestId('org-2')
  expect(org2).toBeVisible()
  expect(org2).toHaveAttribute('aria-disabled', 'true')

  const org3 = screen.getByTestId('org-3')
  expect(org3).toBeVisible()
  expect(org3).toHaveAttribute('aria-disabled', 'true')

  const addOrgsButton = screen.getByTestId('add-orgs')
  expect(addOrgsButton).toHaveTextContent('Add 1')
  await user.click(addOrgsButton)

  const orgs = getOrganizationSuggestionsPayload().organizations
  expect(props.onOrganizationsAdded).toHaveBeenCalledWith([orgs[0]])
})

test('Show error on failed search', async () => {
  const props = {
    ...getOrganizationSelectPanelProps(),
    enterpriseTeamsOrgAssignmentLimit: 1,
  }
  const {user} = render(<OrganizationSelectPanel {...props} />)

  mockVerifiedFetchJSON.mockResolvedValue({
    status: 500,
    ok: false,
  })

  await user.click(screen.getByTestId('select-orgs-button'))

  // Error takes precedence over limit banner
  expect(screen.queryByTestId('org-assignments-limit-error')).not.toBeInTheDocument()
  expect(screen.getByTestId('flash-error')).toBeVisible()
})
