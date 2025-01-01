// NOTE: This test does not include behavior of the secondary query (for example, assignees).
// See ListItemsSecondary.test.tsx for that.
import {Wrapper, setupUserEvent} from '@github-ui/react-core/test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {screen, waitFor, within} from '@testing-library/react'
// eslint-disable-next-line no-restricted-imports
import {useEffect, useLayoutEffect, useRef} from 'react'
import {graphql} from 'react-relay'
import {renderRelay} from '@github-ui/relay-test-utils'
import {TEST_IDS} from '../../../constants/test-ids'

import HyperlistAppWrapper from '../../../test-utils/HyperlistAppWrapper'
import {buildIssue, buildIssues, buildPullRequest} from '../../../test-utils/IssueTestUtils'
import {ListItems} from '../ListItems'
import type {ListItemsSearchRootQuery} from './__generated__/ListItemsSearchRootQuery.graphql'
import type {OpenClosedTabsQuery} from '../header/__generated__/OpenClosedTabsQuery.graphql'
import {noop} from '@github-ui/noop'
import PreloadedQueryBoundary from '@github-ui/relay-preloaded-query-boundary'
import {ListError} from '../ListError'
import {useQueryContext, useQueryEditContext} from '../../../contexts/QueryContext'

jest.mock('@github-ui/react-core/use-app-payload')
jest.setTimeout(60000)

const mockedUseAppPayload = jest.mocked(useAppPayload)
const userEvent = setupUserEvent()
const issueTitle = 'my super specific issue title'
const pullRequestTitle = 'my super specific pull request title'
const executeQueryFunction = jest.fn()

const searchRoot = graphql`
  query ListItemsSearchRootQuery($query: String!, $first: Int = 25, $skip: Int = 0, $includeGitData: Boolean = false)
  @relay_test_operation {
    repository(owner: "github", name: "hyperlist-web") {
      ...ListItemsPaginated_results
        @arguments(
          query: $query
          first: $first
          skip: $skip
          labelPageSize: 20
          fetchRepository: true
          includeGitData: $includeGitData
        )
    }
  }
`

type SetupProps = {
  query?: string
  mockOverrides?: Record<string, unknown>
  includeGitData?: boolean
  scoped_repository?: {id: number; name: string; owner: string} | null
  enabledFeatureFlags?: Record<string, boolean>
  isInOrganization?: boolean
}

function setup({
  query = 'is:issue state:open',
  mockOverrides = {},
  includeGitData = false,
  scoped_repository = {id: 1, name: 'hyperlist-web', owner: 'github'},
  enabledFeatureFlags = {},
  isInOrganization = false,
}: SetupProps = {}) {
  const {environment} = createRelayMockEnvironment()

  mockedUseAppPayload.mockReturnValue({
    initial_view_content: {
      initial_view_content: {},
      preloaded_records: [],
    },
    scoped_repository,
    enabled_features: enabledFeatureFlags,
    query,
  })

  renderRelay<{
    searchQuery: ListItemsSearchRootQuery
    openClosedQuery: OpenClosedTabsQuery
  }>(
    ({queryData: {searchQuery}}) => {
      const listRef = useRef<HTMLUListElement | undefined>(undefined)
      const {setExecuteQuery, setActiveSearchQuery} = useQueryContext()
      const {setDirtySearchQuery} = useQueryEditContext()
      const repoKey = searchQuery.repository!
      useLayoutEffect(() => {
        setActiveSearchQuery(query)
        setDirtySearchQuery(query)
      })
      useEffect(() => {
        if (executeQueryFunction) setExecuteQuery(() => executeQueryFunction)
      }, [setExecuteQuery])

      return (
        <ListItems
          search={repoKey}
          listRef={listRef}
          isBulkSupported
          includeGitDataFromMainQuery={includeGitData}
          isInOrganization={isInOrganization}
        />
      )
    },
    {
      relay: {
        queries: {
          searchQuery: {
            type: 'fragment',
            query: searchRoot,
            variables: {
              query,
              includeGitData,
            },
          },
          openClosedQuery: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          SearchResultItemConnection() {
            return {
              openIssueCount: 6,
              closedIssueCount: 2,
              edges: buildIssues({title: issueTitle, number: 6}),
              issueCount: 8,
            }
          },
          ...mockOverrides,
        },
      },
      wrapper: ({children}) => (
        <Wrapper>
          <HyperlistAppWrapper environment={environment}>
            <PreloadedQueryBoundary fallback={ListError} onRetry={noop}>
              {children}
            </PreloadedQueryBoundary>
          </HyperlistAppWrapper>
        </Wrapper>
      ),
    },
  )
  return {environment}
}

beforeEach(() => {
  jest.clearAllMocks()
})

test('renders issues list with open closed tabs in repo scope', async () => {
  const issue = buildIssue()

  setup({
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 1,
          closedIssueCount: 2,
          edges: [
            {
              node: issue,
            },
          ],
        }
      },
    },
  })
  await screen.findByText(issue.title)

  const sectionFilter1 = screen.getByTestId('list-view-section-filter-0')
  expect(sectionFilter1.textContent).toContain('Open1')
  const sectionFilter2 = screen.getByTestId('list-view-section-filter-1')
  expect(sectionFilter2.textContent).toContain('Closed2')
})

test('renders ListError when edges are null (meaning ES performance is degraded)', async () => {
  jest.spyOn(console, 'error').mockImplementation() // there is a console.error call we need to mock here
  setup({
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          edges: null,
        }
      },
    },
  })

  expect(screen.getByText('Failed to load issues.')).toBeInTheDocument()
})

test('renders required elements for issue list items', async () => {
  const issue = buildIssue()

  setup({
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 1,
          closedIssueCount: 2,
          edges: [
            {
              node: issue,
            },
          ],
        }
      },
    },
  })

  await screen.findByText(issue.title)
  screen.getByText(issue.labels.nodes[0]!.name)

  // Issue Status
  const status = screen.getByTestId(TEST_IDS.listRowStateIcon)
  // eslint-disable-next-line testing-library/no-node-access -- no way to get at it otherwise
  expect(status.querySelector('svg[aria-hidden="true"]')).toBeInTheDocument()
})

test('renders required elements for pull request list items', async () => {
  const pullRequest = buildPullRequest()

  setup({
    includeGitData: true,
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 1,
          closedIssueCount: 2,
          edges: [
            {
              node: pullRequest,
            },
          ],
        }
      },
    },
  })

  await screen.findByText(pullRequest.title)
  screen.getByText(pullRequest.labels.nodes[0]!.name)

  // PR Status
  const status = screen.getByTestId(TEST_IDS.listRowStateIcon)
  // eslint-disable-next-line testing-library/no-node-access -- no way to get at it otherwise
  expect(status.querySelector('svg[aria-hidden="true"]')).toBeInTheDocument()

  // Check Run Status
  screen.getByLabelText('See all checks')
  screen.getByText(`5/${pullRequest.headCommit.commit.statusCheckRollup.contexts.checkRunCount}`)
  expect(screen.getByTestId('checks-status-badge-icon-only')).toBeTruthy()
})

test('renders sorting menu with correct sorting option if sort param is not passed in query', async () => {
  const issue = buildIssue({title: issueTitle})
  setup({
    scoped_repository: null,
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 1,
          closedIssueCount: 2,
          edges: [
            {
              node: issue,
            },
          ],
        }
      },
    },
  })
  await screen.findByText(/my super specific issue title/)
  const sortMenu = await screen.findByTestId('action-bar-item-sort-by')
  const sortButton = within(sortMenu).getByRole('button')
  await waitFor(() => expect(sortButton).toBeEnabled())
  await userEvent.click(sortButton)
  const sortingLabel = await (await screen.findAllByText('Newest'))[0]
  expect(sortingLabel).toBeInTheDocument()
})

test('show repository owner and name when not scoped to a repository', async () => {
  const issue = buildIssue()
  setup({
    scoped_repository: null,
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 1,
          closedIssueCount: 2,
          edges: [
            {
              node: issue,
            },
          ],
        }
      },
    },
  })

  await screen.findByText(issue.title)

  const repoNameAndNumberEl = screen.getByTestId(TEST_IDS.listRowRepoNameAndNumber)
  within(repoNameAndNumberEl).getByText(`${issue.repository.owner.login}/${issue.repository.name}`)
  expect(within(repoNameAndNumberEl).getByText(`#${issue.number}`)).toBeInTheDocument()
})

test('do not show repository owner and name when scoped to a repository', async () => {
  const issue = buildIssue()
  setup({
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 1,
          closedIssueCount: 2,
          edges: [
            {
              node: issue,
            },
          ],
        }
      },
    },
  })

  await screen.findByText(issue.title)

  const repoNameAndNumberEl = screen.getByTestId(TEST_IDS.listRowRepoNameAndNumber)
  const repoNwo = within(repoNameAndNumberEl).queryByText(`${issue.repository.owner.login}/${issue.repository.name}`)
  expect(repoNwo).toBeNull()

  within(repoNameAndNumberEl).getByText(`#${issue.number}`)
})

test('show no result indicators when there are no results in a scope repo', async () => {
  setup({
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 0,
          closedIssueCount: 0,
          issueCount: 0,
          edges: [],
        }
      },
    },
  })

  expect(screen.getByText('No results')).toBeInTheDocument()
})

test('show pagination options in wrong page', async () => {
  setup({
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 100,
          closedIssueCount: 0,
          issueCount: 100,
          edges: [],
        }
      },
    },
  })

  expect(screen.getByText('No results')).toBeInTheDocument()

  const paginationArea = screen.getByRole('navigation', {name: 'Pagination'})
  expect(paginationArea).toBeInTheDocument()
})

test('does not allow selections when query supports PR', async () => {
  setup({
    query: 'state:open',
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 1,
          closedIssueCount: 2,
          edges: [
            {
              node: buildIssue({title: issueTitle}),
            },
            {
              node: buildPullRequest({title: pullRequestTitle}),
            },
          ],
        }
      },
    },
  })

  const items = screen.getAllByTestId('list-view-item-trailing-badge')
  expect(items).toHaveLength(2)
  expect(items[0]).toHaveTextContent('bug') // Label
  expect(items[1]).toHaveTextContent('bug') // Label

  // select all checkbox should not be present
  expect(screen.queryByTestId('select-all-checkbox')).not.toBeInTheDocument()

  // list item checkboxes should not be present
  expect(screen.queryAllByLabelText(/Select:/)).toHaveLength(0)

  // There should be no bulk actions available
  expect(screen.queryByTestId('list-view-actions')).not.toBeInTheDocument()
})

/*
  skipped due to flakiness reported in - https://github.com/github/github/issues/353522
  This should be fixed as part of - https://github.com/github/issues/issues/13440
*/
test('supports shift selection', async () => {
  setup({})
  // Assert nothing is selected in the beginning
  const listElement = screen.getByTestId('list')
  const checkboxes: HTMLInputElement[] = within(listElement).getAllByRole('checkbox')
  let selectedCheckboxes = checkboxes.filter(checkbox => checkbox.checked)
  expect(selectedCheckboxes.length).toBe(0)

  await userEvent.click(screen.getByLabelText(`Select: ${issueTitle} 1`))
  await userEvent.keyboard('{Shift>}')
  await userEvent.click(screen.getByLabelText(`Select: ${issueTitle} 2`))
  await userEvent.keyboard('{/Shift}')

  selectedCheckboxes = checkboxes.filter(checkbox => checkbox.checked)
  expect(selectedCheckboxes.length).toBe(2)

  await userEvent.click(screen.getByLabelText(`Select: ${issueTitle} 4`))
  await userEvent.keyboard('{Shift>}')
  await userEvent.click(screen.getByLabelText(`Select: ${issueTitle} 5`))
  await userEvent.keyboard('{/Shift}')

  // Assert that 12 items are selected
  selectedCheckboxes = checkboxes.filter(checkbox => checkbox.checked)
  expect(selectedCheckboxes.length).toBe(4)

  // // Shift deselect
  await userEvent.click(screen.getByLabelText(`Select: ${issueTitle} 2`))
  await userEvent.keyboard('{Shift>}')
  await userEvent.click(screen.getByLabelText(`Select: ${issueTitle} 4`))
  await userEvent.keyboard('{/Shift}')

  // // Assert that 4 items are selected
  selectedCheckboxes = checkboxes.filter(checkbox => checkbox.checked)
  expect(selectedCheckboxes.length).toBe(2)
}, 40000)

test('renders the issue type filter for organization repositories', async () => {
  const issue = buildIssue()
  setup({
    scoped_repository: {id: 1, name: 'hyperlist-web', owner: 'github'},
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 1,
          closedIssueCount: 2,
          edges: [
            {
              node: issue,
            },
          ],
        }
      },
    },
    isInOrganization: true,
  })

  await screen.findByText(issue.title)

  expect(
    screen.getByRole('button', {
      name: /Filter by issue type/i,
    }),
  ).toBeInTheDocument()
})

test('does not render the issue type filter for user repositories', async () => {
  const issue = buildIssue()
  setup({
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 1,
          closedIssueCount: 2,
          edges: [
            {
              node: issue,
            },
          ],
        }
      },
    },
  })

  await screen.findByText(issue.title)

  expect(
    screen.queryByRole('button', {
      name: /Filter by issue type/i,
    }),
  ).not.toBeInTheDocument()
})

test('Updates url when sorting option is changed as well as the history', async () => {
  const issue = buildIssue()
  setup({
    mockOverrides: {
      SearchResultItemConnection() {
        return {
          openIssueCount: 1,
          closedIssueCount: 2,
          edges: [
            {
              node: issue,
            },
          ],
        }
      },
    },
  })
  await screen.findByText(issue.title)
  const sortMenu = await screen.findByTestId('action-bar-item-sort-by')
  const sortButton = within(sortMenu).getByRole('button')
  await waitFor(() => expect(sortButton).toBeEnabled())
  const replaceState = jest.spyOn(window.history, 'replaceState').mockImplementation(() => {})
  await userEvent.click(sortButton)
  const sortingLabel = await (await screen.findAllByText('Newest'))[0]
  expect(sortingLabel).toBeInTheDocument()

  await userEvent.click(sortingLabel!)

  expect(replaceState).toHaveBeenCalledTimes(1)
})
