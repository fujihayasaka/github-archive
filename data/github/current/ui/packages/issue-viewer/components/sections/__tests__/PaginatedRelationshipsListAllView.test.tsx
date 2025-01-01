import {ThemeProvider} from '@primer/react'
// test imports
import {render, screen, within} from '@testing-library/react'
import {renderRelay} from '@github-ui/relay-test-utils'
import {testIdProps} from '@github-ui/test-id-props'
// tested imports
import {LABELS} from '../../../constants/labels'
import {
  RelationshipsListAllViewPaginated,
  RelationshipsListItem,
  TEST_ID_PULL_REQUEST_METADATA,
  TEST_ID_SKELETON_ITEM,
} from '../relations-section/PaginatedRelationshipsListAllView'
import {graphql} from 'relay-runtime'
import type {PaginatedRelationshipsListAllViewTestQuery} from './__generated__/PaginatedRelationshipsListAllViewTestQuery.graphql'
import {ListView} from '@github-ui/list-view'

const PaginatedRelationshipsListAllViewTestQueryGraphQL = graphql`
  query PaginatedRelationshipsListAllViewTestQuery($id: ID!) @relay_test_operation {
    issue: node(id: $id) {
      ...PaginatedRelationshipsListAllViewItemFragment
    }
  }
`

const setup = (repositoryNWO: string, issue: Record<string, unknown>) => {
  const mockedResponse = generateMockIssue(issue, repositoryNWO)

  const {relayMockEnvironment} = renderRelay<{
    paginatedRelationshipsListAllViewTestQuery: PaginatedRelationshipsListAllViewTestQuery
  }>(
    ctx => (
      <ThemeProvider>
        <ListView title={''}>
          <RelationshipsListItem
            issueFragment={ctx.queryData.paginatedRelationshipsListAllViewTestQuery.issue!}
            sourceIssueRepositoryNameWithOwner={repositoryNWO}
          />
        </ListView>
      </ThemeProvider>
    ),
    {
      relay: {
        queries: {
          paginatedRelationshipsListAllViewTestQuery: {
            type: 'fragment',
            query: PaginatedRelationshipsListAllViewTestQueryGraphQL,
            variables: {id: 'I_001'},
          },
        },
        mockResolvers: {
          Repository({path}) {
            return resolveByPath(mockedResponse, path)
          },
          Issue({path}) {
            return resolveByPath(mockedResponse, path)
          },
          UserConnection({path}) {
            return resolveByPath(mockedResponse, path)
          },
          User({path}) {
            return resolveByPath(mockedResponse, path)
          },
          PullRequestConnection({path}) {
            return resolveByPath(mockedResponse, path)
          },
        },
      },
    },
  )

  return {environment: relayMockEnvironment}
}

describe('PaginatedRelationshipsListAllView', () => {
  test('displays loading state when isLoadingNext is true', async () => {
    const loadingListId = '__test-paginated-list-view-loading'
    const loadedListId = '__test-paginated-list-view'
    const props = {accessibleTitle: 'accessible title', hasNextPage: false, onLoadMore: () => null}
    render(
      <>
        <div {...testIdProps(loadingListId)}>
          <RelationshipsListAllViewPaginated {...props} isLoadingNext />
        </div>
        <div {...testIdProps(loadedListId)}>
          <RelationshipsListAllViewPaginated {...props} isLoadingNext={false} />
        </div>
      </>,
    )

    // loading state displays skeleton rows
    expect(within(screen.getByTestId(loadingListId)).getAllByTestId(TEST_ID_SKELETON_ITEM).length).toBeGreaterThan(0)
    // not loading state won't display skeleton rows
    expect(within(screen.getByTestId(loadedListId)).queryAllByTestId(TEST_ID_SKELETON_ITEM).length).toBe(0)
  })

  test('displays load more button when hasNextPage is true', async () => {
    const hasNextPageId = '__test-paginated-list-view-with-next-page'
    const fullyLoadedId = '__test-padinated-list-view-fully-loaded'
    const props = {accessibleTitle: 'accessible title', isLoadingNext: false, onLoadMore: () => null}

    render(
      <>
        <div {...testIdProps(hasNextPageId)}>
          <RelationshipsListAllViewPaginated {...props} hasNextPage />
        </div>
        <div {...testIdProps(fullyLoadedId)}>
          <RelationshipsListAllViewPaginated {...props} hasNextPage={false} />
        </div>
      </>,
    )

    expect(
      within(screen.getByTestId(hasNextPageId)).getByRole('button', {name: LABELS.loadMoreItems}),
    ).toBeInTheDocument()

    expect(
      within(screen.getByTestId(fullyLoadedId)).queryByRole('button', {name: LABELS.loadMoreItems}),
    ).not.toBeInTheDocument()
  })

  test('invokes callback onLoadMore when button is clicked', async () => {
    const onLoadMore = jest.fn()
    const props = {accessibleTitle: 'accessible title', isLoadingNext: false}

    render(<RelationshipsListAllViewPaginated {...props} hasNextPage onLoadMore={onLoadMore} />)

    const button = screen.getByRole('button', {name: LABELS.loadMoreItems})

    button.click()

    expect(onLoadMore).toHaveBeenCalledTimes(1)
  })

  test('disables onLoadMore button when list is loading', async () => {
    const props = {accessibleTitle: 'accessible title', hasNextPage: true, onLoadMore: () => null}

    render(<RelationshipsListAllViewPaginated {...props} isLoadingNext />)

    const button = screen.getByRole('button', {name: LABELS.loadMoreItems})
    expect(button).toBeInTheDocument()
    expect(button).toHaveAttribute('disabled')
  })
})

describe('RelationshipsListItem', () => {
  test('renders the details of an item fragment and simple repository description when target issue belongs to the same repository of source issue', async () => {
    const sourceRepository = 'user/repo'
    const issue = {
      number: 1,
      title: 'Issue A',
      url: 'http://gh.com/issue-url/1',
      repository: {
        nameWithOwner: sourceRepository,
      },
      state: 'open',
    }

    setup(sourceRepository, issue)

    expect(screen.getByTestId('list-view-item-title-container')).toHaveTextContent(issue.title)
    expect(screen.getByTestId('listitem-title-link')).toHaveAttribute('href', issue.url)
    expect(screen.getByTestId('list-view-item-description')).toHaveTextContent(`#${issue.number}`)
  })

  test("renders the details of an item fragment and a full issue reference when the target issue doesn't belong to the same repository of the source issue", async () => {
    const sourceRepository = 'user/repo'
    const targetRepository = 'other-user/other-repo'
    const issue = {
      number: 2,
      title: 'Issue B',
      url: 'http://gh.com/issue-url/2',
      repository: {
        nameWithOwner: targetRepository,
      },
      state: 'closed',
    }

    setup(sourceRepository, issue)

    expect(screen.getByTestId('list-view-item-title-container')).toHaveTextContent(issue.title)
    expect(screen.getByTestId('listitem-title-link')).toHaveAttribute('href', issue.url)
    expect(screen.getByTestId('list-view-item-description')).toHaveTextContent(`${targetRepository}#${issue.number}`)
  })

  test('renders assignees metadata if the issue has any', async () => {
    const sourceRepository = 'user/repo'
    const assignees = [
      {
        login: 'monalisa',
        avatarUrl: 'https://alambic.gh.com/avartars/u/monalisa',
      },
      {
        login: 'nasquasha',
        avatarUrl: 'https://alambic.gh.com/avartars/u/nasquasha',
      },
    ]

    const issue = {
      number: 4,
      title: 'Issue B',
      url: 'http://gh.com/user/repo/issues/4',
      repository: {
        nameWithOwner: sourceRepository,
      },
      state: 'closed',
      stateReason: 'not_planned',
      assignees: {
        totalCount: 4,
        edges: assignees.map(a => ({node: a})),
      },
    }

    setup(sourceRepository, issue)

    const avatars = screen.getAllByTestId('github-avatar')
    expect(avatars.length).toBe(assignees.length)

    for (let i = 0; i < avatars.length; i += 1) {
      const avatarElement = avatars[i]
      const expectedImgSrc = `${assignees[i]!.avatarUrl}?size=40`

      expect(avatarElement).toHaveAttribute('src', expectedImgSrc)
    }

    expect(screen.getByTestId('list-view-item-title-container')).toHaveTextContent(issue.title)
    expect(screen.getByTestId('listitem-title-link')).toHaveAttribute('href', issue.url)
  })

  test('renders a pull request metadata link', async () => {
    const sourceRepository = 'user/repo'

    const issue = {
      number: 4,
      title: 'Issue B',
      url: 'http://gh.com/user/repo/issues/4',
      repository: {
        nameWithOwner: sourceRepository,
      },
      state: 'closed',
      stateReson: 'not_planned',
      closedByPullRequestsReferences: {
        totalCount: 1,
      },
    }

    setup(sourceRepository, issue)

    expect(screen.getByTestId(TEST_ID_PULL_REQUEST_METADATA)).not.toBeEmptyDOMElement()
  })
})

let currentMockIssueId = 1
const generateMockIssue = (issue: Record<string, unknown>, repositoryNameWithOwner: string) => {
  if (!issue.number) issue.number = currentMockIssueId++
  if (!issue.id) issue.id = `I_${issue.number}`
  if (!issue.repository) issue.repository = {nameWithOwner: repositoryNameWithOwner} as Record<string, unknown>
  if (!issue.url) {
    const repository = issue.repository as Record<string, unknown>
    const nameWithOwner = repository.nameWithOwner
    issue.url = `gh.com/${nameWithOwner}/issues/${issue.number}`
  }
  if (!issue.titleHTML) issue.titleHTML = issue.title
  if (!issue.state) issue.state = 'open'

  return {issue}
}

const resolveByPath = (mockData: Record<string, unknown>, paths: readonly string[] | null | undefined) => {
  if (!paths) return {}

  let pathData = mockData
  for (const pathPart of paths) {
    if (!pathData || !pathData.hasOwnProperty(pathPart)) return {}
    pathData = pathData[pathPart] as Record<string, unknown>
  }
  return pathData
}
