import {act, screen, within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {BusinessTeamsListView} from '../routes/BusinessTeamsListView'
import {
  getBusinessTeamsTableViewNoAssignmentRoutePayload,
  getBusinessTeamsTableViewRoutePayload,
} from '../test-utils/mock-data'
import {verifiedFetchJSON} from '@github-ui/verified-fetch'

const mockNavigate = jest.fn()
jest.mock('@github-ui/use-navigate', () => ({
  useNavigate: jest.fn(() => mockNavigate),
  useSearchParams: jest.fn(() => [new URLSearchParams(), jest.fn()]),
}))
const mockVerifiedFetchJSON = verifiedFetchJSON as jest.Mock
// eslint-disable-next-line no-restricted-syntax
jest.mock('@github-ui/verified-fetch', () => ({
  verifiedFetchJSON: jest.fn(),
}))

test('Renders the BusinessTeamsTableView', () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const createButton = screen.getByRole('button', {name: /Create Enterprise team/i})
  expect(createButton).toBeInTheDocument()

  const teamLimitBanner = screen.queryByTestId('teams-limit-error')
  expect(teamLimitBanner).not.toBeInTheDocument()

  const teamName = screen.getByText(/Acme Engineering/i)
  const teamDescription = screen.getByText(/Acme Corp's engineering team/i)
  expect(teamName).toBeInTheDocument()
  expect(teamDescription).toBeInTheDocument()

  const listActions = screen.getByTestId('action-bar-container')
  expect(listActions).toBeInTheDocument()
})

test('Create Enterprise team button is inactive and shows a banner and tooltip when limit has been reached', async () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  routePayload.enterpriseTeamsLimitReached = true
  routePayload.enterpriseTeamsLimit = 1
  const {user} = render(<BusinessTeamsListView />, {
    routePayload,
  })

  const createButton = screen.getByRole('button', {name: /Create Enterprise team/i})
  expect(createButton).toHaveAttribute('data-inactive', 'true')

  const teamLimitBanner = screen.getByTestId('teams-limit-error')
  expect(teamLimitBanner).toBeInTheDocument()

  await user.hover(createButton)
  const toolTipLimit = screen.getByText(`Cannot add more teams, you've reached the 1-team limit.`)
  expect(toolTipLimit).toBeVisible()
})

test('Hides the Create Enterprise button when user is not allowed to create new teams', async () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  routePayload.canCreateNewTeams = false
  routePayload.enterpriseTeamsLimitReached = true
  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const createButton = screen.queryByRole('button', {name: /Create Enterprise team/i})
  expect(createButton).not.toBeInTheDocument()
})

test('Does not link Enterprise teams when user is not an owner', async () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  routePayload.isOwner = false
  routePayload.enterpriseTeamsLimitReached = true
  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const teamLink = screen.queryByRole('link', {name: 'Acme Engineering'})
  expect(teamLink).not.toBeInTheDocument()

  const teamTitle = screen.queryByText('Acme Engineering')
  expect(teamTitle).toBeInTheDocument()

  const listActions = screen.queryByTestId('action-bar-container')
  expect(listActions).not.toBeInTheDocument()
})

test('Navigates to the Create Enterprise team page', async () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  const {user} = render(<BusinessTeamsListView />, {
    routePayload,
  })

  const createButton = screen.getByRole('button', {name: /Create Enterprise team/i})
  await user.click(createButton)

  expect(mockNavigate).toHaveBeenCalledWith(routePayload.createTeamUrl)
})

test('Navigates to the Enterprise team page on title click', async () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  render(<BusinessTeamsListView />, {
    routePayload,
  })

  expect(screen.getByRole('link', {name: 'Acme Engineering'})).toHaveAttribute(
    'href',
    '/enterprises/acme-corp/teams/acme-engineering',
  )
})

test('Renders the table with correct columns', () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const teamNameHeader = screen.getByTestId('list-view-header-title')
  const filterDropdownHeader = screen.getByTestId('filterDropdown-header')
  const densityToggle = screen.getByTestId('density-toggle')

  expect(teamNameHeader).toBeInTheDocument()
  expect(filterDropdownHeader).toBeInTheDocument()
  expect(densityToggle).toBeInTheDocument()
})

test('Renders the correct ActionMenu items', async () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const menuAnchor = screen.getByRole('button', {name: 'More list item action bar'})

  expect(menuAnchor).toBeInTheDocument()

  act(() => menuAnchor.click())

  const viewItem = screen.getByRole('menuitem', {name: 'View'})
  expect(viewItem).toBeInTheDocument()

  const assignItem = screen.queryByRole('menuitem', {name: /Assign Enterprise role/})
  expect(assignItem).toBeInTheDocument()

  const editItem = screen.getByRole('menuitem', {name: /Edit/})
  expect(editItem).toBeInTheDocument()

  const deleteItem = screen.getByRole('menuitem', {name: /Delete/})
  expect(deleteItem).toBeInTheDocument()
})

test('Renders the correct ActionMenu items when user is not eligible to assign roles', async () => {
  const routePayload = getBusinessTeamsTableViewNoAssignmentRoutePayload()
  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const menuAnchor = screen.getByRole('button', {name: 'More list item action bar'})

  expect(menuAnchor).toBeInTheDocument()

  act(() => menuAnchor.click())

  const viewItem = screen.getByRole('menuitem', {name: 'View'})
  expect(viewItem).toBeInTheDocument()

  const assignItem = screen.queryByRole('menuitem', {name: /Assign Enterprise role/})
  expect(assignItem).not.toBeInTheDocument()

  const editItem = screen.getByRole('menuitem', {name: /Edit/})
  expect(editItem).toBeInTheDocument()

  const deleteItem = screen.getByRole('menuitem', {name: /Delete/})
  expect(deleteItem).toBeInTheDocument()
})

test('Shows no teams message when there are no Enterprise teams', () => {
  const routePayload = {
    ...getBusinessTeamsTableViewRoutePayload(),
    enterpriseTeams: [],
    totalTeamsCount: 0,
  }

  const {user} = render(<BusinessTeamsListView />, {
    routePayload,
  })

  const noTeamsHeading = screen.getByRole('heading', {
    name: /you have no enterprise teams/i,
  })
  expect(noTeamsHeading).toBeInTheDocument()

  const description = screen.getByText(/get started by creating a new enterprise team/i)
  expect(description).toBeInTheDocument()

  const createButton = screen.getByRole('button', {name: /create enterprise team/i})
  expect(createButton).toBeInTheDocument()

  user.click(createButton)
  expect(mockNavigate).toHaveBeenCalledWith(routePayload.createTeamUrl)

  const readMoreLink = screen.getByRole('link', {name: /read more about enterprise teams/i})
  expect(readMoreLink).toHaveAttribute(
    'href',
    'https://docs.github.com/organizations/organizing-members-into-teams/about-teams',
  )
})

test('Shows no teams message when there are no Enterprise teams for non-owner user,', () => {
  const routePayload = {
    ...getBusinessTeamsTableViewRoutePayload(),
    enterpriseTeams: [],
    totalTeamsCount: 0,
  }
  routePayload.canCreateNewTeams = false

  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const noTeamsHeading = screen.getByRole('heading', {
    name: /you have no enterprise teams/i,
  })
  expect(noTeamsHeading).toBeInTheDocument()

  const description = screen.queryByText(/get started by creating a new enterprise team/i)
  expect(description).not.toBeInTheDocument()

  const createButton = screen.queryByRole('button', {name: /create enterprise team/i})
  expect(createButton).not.toBeInTheDocument()

  const readMoreLink = screen.getByRole('link', {name: /read more about enterprise teams/i})
  expect(readMoreLink).toHaveAttribute(
    'href',
    'https://docs.github.com/organizations/organizing-members-into-teams/about-teams',
  )
})

test('Shows no teams found message when there are no Enterprise teams with a search query', () => {
  const routePayload = {
    ...getBusinessTeamsTableViewRoutePayload(),
    enterpriseTeams: [],
    totalTeamsCount: 0,
    meta: {
      ...getBusinessTeamsTableViewRoutePayload().meta,
      filter: 'acme',
    },
  }

  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const noTeamsHeading = screen.getByRole('heading', {
    name: /We couldn’t find any matching teams./i,
  })
  expect(noTeamsHeading).toBeInTheDocument()

  const description = screen.getByText(
    /No teams match your search criteria. Adjust your search or clear the filter to view all teams./i,
  )
  expect(description).toBeInTheDocument()
})

test('Shows 1 Team (non plural) in the column header when there is 1 team', () => {
  const routePayload = {
    ...getBusinessTeamsTableViewRoutePayload(),
    enterpriseTeams: [
      {
        id: 1,
        name: 'Acme Engineering',
        description: "Acme Corp's engineering team",
        memberCount: 10,
        slug: 'acme-engineering',
        viewTeamUrl: '/teams/acme-engineering',
        editTeamUrl: '/teams/acme-engineering/edit',
      },
    ],
    totalTeamsCount: 1,
  }

  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const teamCountHeader = screen.getByText(/1 Team/i)
  expect(teamCountHeader).toBeInTheDocument()
})

test('Shows 2 Teams (plural) in the column header when there are 2 teams', () => {
  const routePayload = {
    ...getBusinessTeamsTableViewRoutePayload(),
    enterpriseTeams: [
      {
        id: 1,
        name: 'Acme Engineering',
        description: "Acme Corp's engineering team",
        memberCount: 10,
        slug: 'acme-engineering',
        viewTeamUrl: '/teams/acme-engineering',
        editTeamUrl: '/teams/acme-engineering/edit',
      },
      {
        id: 2,
        name: 'Acme Marketing',
        description: "Acme Corp's marketing team",
        memberCount: 5,
        slug: 'acme-marketing',
        viewTeamUrl: '/teams/acme-marketing',
        editTeamUrl: '/teams/acme-marketing/edit',
      },
    ],
    totalTeamsCount: 2,
  }

  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const teamCountHeader = screen.getByText(/2 Teams/i)
  expect(teamCountHeader).toBeInTheDocument()
})

test('Shows Last added as the default sort option', () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const sortDropdown = screen.getByTestId('filterDropdown-header')
  expect(sortDropdown).toHaveTextContent(/Last added/i)
})

test('Search makes a call to the server with the search query', async () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()
  const {user} = render(<BusinessTeamsListView />, {
    routePayload,
  })

  mockVerifiedFetchJSON.mockResolvedValue({
    ok: true,
    statusText: 'OK',
    json: async () => {
      return {
        payload: {
          ...routePayload,
          enterpriseTeams: [
            {
              name: 'something-new',
              id: 1,
              memberCount: 15,
              slug: 'something-new',
              description: 'something-new',
              viewTeamUrl: '/enterprises/acme-corp/teams/something-new',
              editTeamUrl: '/enterprises/acme-corp/teams/something-new/edit',
            },
          ],
          meta: {
            ...routePayload.meta,
            filter: 'something-new',
          },
        },
      }
    },
  })

  const searchInput = screen.getByTestId('search-input')
  await user.type(searchInput, 'something-new')

  expect(searchInput).toHaveValue('something-new')
})

test('Displays the correct total team count in the column header', () => {
  const routePayload = {
    ...getBusinessTeamsTableViewRoutePayload(),
    totalTeamsCount: 12,
  }

  render(<BusinessTeamsListView />, {
    routePayload,
  })

  const teamCountHeader = screen.getByText(/12 Teams/i)
  expect(teamCountHeader).toBeInTheDocument()
})

test('Displays IdP group label for teams linked to external groups', () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()

  // TypeScript non-null assertion tells TypeScript we know this value exists
  const firstTeam = routePayload.enterpriseTeams[0]!
  firstTeam.linkedToExternalGroup = true

  render(<BusinessTeamsListView />, {
    routePayload,
  })

  // Find the team's list item using the stored team
  const listItem = screen.getByTestId(`list-item-${firstTeam.id}`)

  // Verify that the IdP group label is within this list item
  const idpGroupLabel = within(listItem).getByText('IdP group')
  expect(idpGroupLabel).toBeInTheDocument()
})

test('Does not display IdP group label for teams not linked to external groups', () => {
  const routePayload = getBusinessTeamsTableViewRoutePayload()

  // TypeScript non-null assertion tells TypeScript we know this value exists
  const firstTeam = routePayload.enterpriseTeams[0]!
  firstTeam.linkedToExternalGroup = false

  render(<BusinessTeamsListView />, {
    routePayload,
  })

  // Find the team's list item using the stored team
  const listItem = screen.getByTestId(`list-item-${firstTeam.id}`)

  // Verify that the IdP group label is NOT within this list item
  const idpGroupLabel = within(listItem).queryByText('IdP group')
  expect(idpGroupLabel).not.toBeInTheDocument()
})
