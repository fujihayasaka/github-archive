// NOTE: This test explicitly includes behavior of the secondary query (when includeGitData is false)
import {Wrapper} from '@github-ui/react-core/test-utils'
import {renderRelay} from '@github-ui/relay-test-utils'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {screen, within} from '@testing-library/react'
import {useRef} from 'react'
import {graphql} from 'react-relay'
import type {createMockEnvironment} from 'relay-test-utils'
import {TEST_IDS} from '../../../constants/test-ids'
import HyperlistAppWrapper from '../../../test-utils/HyperlistAppWrapper'
import {buildIssue, buildPullRequest} from '../../../test-utils/IssueTestUtils'
import {ListItems} from '../ListItems'
import type {ListItemsSecondarySearchRootQuery} from './__generated__/ListItemsSecondarySearchRootQuery.graphql'
import {IssuesIndexSecondaryGraphqlQuery} from '@github-ui/list-view-items-issues-prs/IssueRow'
import type {IssueRowSecondaryQuery} from '@github-ui/list-view-items-issues-prs/IssuesIndexSecondaryQuery'
import type {ListItemsPaginated_results$key} from '../__generated__/ListItemsPaginated_results.graphql'

jest.mock('@github-ui/react-core/use-app-payload')

jest.setTimeout(60000)

const mockedUseAppPayload = jest.mocked(useAppPayload)

const searchRoot = graphql`
  query ListItemsSecondarySearchRootQuery(
    $query: String = "state:open archived:false assignee:@me sort:updated-desc"
    $first: Int = 25
    $labelPageSize: Int = 20
    $skip: Int = null
    $includeGitData: Boolean = false
  ) @relay_test_operation {
    ...ListItemsPaginated_results
      @arguments(
        query: $query
        first: $first
        skip: $skip
        labelPageSize: $labelPageSize
        fetchRepository: true
        includeGitData: $includeGitData
      )
  }
`

function mockRoute(query: string, enabledFeatures: {[key: string]: boolean | undefined} = {}) {
  mockedUseAppPayload.mockReturnValue({
    initial_view_content: {},
    enabled_features: {...enabledFeatures},
    scoped_repository: '',
    query,
  })
}

beforeEach(() => {
  jest.clearAllMocks()
})

type TestComponentForRenderRelayProps = {
  query: string
  environment: ReturnType<typeof createMockEnvironment>
  search: ListItemsPaginated_results$key
  enabledFeatureFlags?: {[key: string]: boolean | undefined}
  includeGitDataFromMainQuery?: boolean
}

function TestComponentForRenderRelay({
  query,
  environment,
  search,
  enabledFeatureFlags,
  includeGitDataFromMainQuery = false,
}: TestComponentForRenderRelayProps) {
  mockRoute(query, enabledFeatureFlags)
  const listRef = useRef(undefined)

  return (
    <HyperlistAppWrapper environment={environment}>
      <ListItems
        search={search}
        listRef={listRef}
        isBulkSupported
        includeGitDataFromMainQuery={includeGitDataFromMainQuery}
      />
    </HyperlistAppWrapper>
  )
}

type IssueOrPull = ReturnType<typeof buildIssue> | ReturnType<typeof buildPullRequest>

type SetupProps = {
  query?: string
  nodes?: IssueOrPull[]
  includeGitDataFromMainQuery?: boolean
  enabledFeatureFlags?: {[key: string]: boolean}
}

function setup({
  query = 'state:open is:issue sort:created-desc',
  nodes = [],
  includeGitDataFromMainQuery = false,
  enabledFeatureFlags = {},
}: SetupProps = {}) {
  return renderRelay<{
    searchRootQuery: ListItemsSecondarySearchRootQuery
    secondaryQuery: IssueRowSecondaryQuery
  }>(
    ({queryData, relayMockEnvironment}) => {
      return (
        <TestComponentForRenderRelay
          environment={relayMockEnvironment}
          search={queryData.searchRootQuery}
          query={query}
          enabledFeatureFlags={enabledFeatureFlags}
          includeGitDataFromMainQuery={includeGitDataFromMainQuery}
        />
      )
    },
    {
      relay: {
        queries: {
          searchRootQuery: {
            type: 'fragment',
            query: searchRoot,
            variables: {query, first: 25, labelPageSize: 20, includeGitData: includeGitDataFromMainQuery},
          },
          secondaryQuery: {
            type: 'preloaded',
            query: IssuesIndexSecondaryGraphqlQuery,
            variables: {nodes: nodes.map(node => node.id), includeReactions: false, assigneePageSize: 10},
          },
        },
        mockResolvers: {
          SearchResultItemConnection() {
            return {
              openIssueCount: 1,
              closedIssueCount: 0,
              edges: nodes.map(node => ({node})),
            }
          },
          Query() {
            return {
              nodes,
            }
          },
        },
      },
      wrapper: Wrapper,
    },
  )
}

test('renders required elements including status check rollup for pull request list items with pull_request_single_subscription when includeGitData is true', async () => {
  const query = 'state:open is:pr sort:created-desc'
  const pullRequest = buildPullRequest()

  setup({query, nodes: [pullRequest], enabledFeatureFlags: {pull_request_single_subscription: true}})

  await screen.findByText(pullRequest.title)
  screen.getByText(pullRequest.labels.nodes[0]!.name)

  // PR Status
  const status = screen.getByTestId(TEST_IDS.listRowStateIcon)
  // eslint-disable-next-line testing-library/no-node-access -- no way to get at it otherwise
  expect(status.querySelector('svg[aria-hidden="true"]')).toBeInTheDocument()

  // Check Run Status
  screen.getByLabelText('See all checks')
  screen.getByText(`5/${pullRequest.statusCheckRollup.contexts.checkRunCount}`)
  expect(screen.getByTestId('checks-status-badge-icon-only')).toBeTruthy()

  // repo name and number (e.g. "hyperlist-web#123")
  const repoNameAndNumberEl = screen.getByTestId(TEST_IDS.listRowRepoNameAndNumber)
  expect(
    within(repoNameAndNumberEl).getByText(`${pullRequest.repository.owner.login}/${pullRequest.repository.name}`),
  ).toBeTruthy()
  expect(within(repoNameAndNumberEl).getByText(`#${pullRequest.number}`)).toBeTruthy()
})

test('renders required elements including status check rollup for pull request list items with pull_request_single_subscription when includeGitData is false', async () => {
  const query = 'state:open is:pr sort:created-desc'
  const pullRequest = buildPullRequest()

  setup({
    query,
    nodes: [pullRequest],
    includeGitDataFromMainQuery: true,
    enabledFeatureFlags: {pull_request_single_subscription: true},
  })

  await screen.findByText(pullRequest.title)
  screen.getByText(pullRequest.labels.nodes[0]!.name)

  // PR Status
  const status = screen.getByTestId(TEST_IDS.listRowStateIcon)
  // eslint-disable-next-line testing-library/no-node-access -- no way to get at it otherwise
  expect(status.querySelector('svg[aria-hidden="true"]')).toBeInTheDocument()

  // Check Run Status
  screen.getByLabelText('See all checks')
  screen.getByText(`5/${pullRequest.statusCheckRollup.contexts.checkRunCount}`)
  expect(screen.getByTestId('checks-status-badge-icon-only')).toBeTruthy()

  // repo name and number (e.g. "hyperlist-web#123")
  const repoNameAndNumberEl = screen.getByTestId(TEST_IDS.listRowRepoNameAndNumber)
  expect(
    within(repoNameAndNumberEl).getByText(`${pullRequest.repository.owner.login}/${pullRequest.repository.name}`),
  ).toBeTruthy()
  expect(within(repoNameAndNumberEl).getByText(`#${pullRequest.number}`)).toBeTruthy()
})

test('Sets the correct href on the avatar stack', async () => {
  setup({
    query: 'is:issue state:open',
    nodes: [buildIssue()],
  })

  const assignee = await screen.findByLabelText('testassignee1login is assigned')

  expect(assignee).toHaveAttribute('href', '/issues?q=is%3Aissue%20state%3Aopen%20assignee%3Atestassignee1login')
})

test('Renders sub-issues summary badge when sub_issues flag is enabled', async () => {
  setup({
    enabledFeatureFlags: {sub_issues: true},
    query: 'is:issue state:open',
    nodes: [buildIssue()],
  })

  const subIssuesSummary = (await screen.findAllByTestId('list-view-item-trailing-badge'))[0]
  expect(subIssuesSummary).toHaveTextContent('0 / 1')
})

test('Does not render sub-issues summary badge when sub_issues flag is disabled', async () => {
  setup({
    enabledFeatureFlags: {sub_issues: false},
    query: 'is:issue state:open',
    nodes: [buildIssue()],
  })

  const firstBadge = (await screen.findAllByTestId('list-view-item-trailing-badge'))[0]
  expect(firstBadge).not.toHaveTextContent('0 / 1')
})
