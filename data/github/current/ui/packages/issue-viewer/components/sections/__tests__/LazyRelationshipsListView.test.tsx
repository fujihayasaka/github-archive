import {Suspense, type ReactNode} from 'react'
import {ThemeProvider} from '@primer/react'
// test imports
import {act, render, screen} from '@testing-library/react'
import {renderRelay} from '@github-ui/relay-test-utils'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import {RelayEnvironmentProvider} from 'react-relay'
// tested imports
import {LazyRelationshipsBlockedByListView} from '../relations-section/LazyRelationshipsBlockedByListView'
import type {LazyRelationshipsBlockedByListViewQuery} from '../relations-section/__generated__/LazyRelationshipsBlockedByListViewQuery.graphql'
import {LazyRelationshipsBlockingListView} from '../relations-section/LazyRelationshipsBlockingListView'
import type {LazyRelationshipsBlockingListViewQuery} from '../relations-section/__generated__/LazyRelationshipsBlockingListViewQuery.graphql'
import {LABELS} from '../../../constants/labels'

const defaultTestRepository = 'test-user/test-repo'
const setup = (relationType: string, issues: Array<Record<string, unknown>>, lazyComponent: ReactNode) => {
  const mockedResponse = generateMock('issue', relationType, issues)

  const {relayMockEnvironment} = renderRelay<{
    lazyRelationshipsBlockedByListViewQuery: LazyRelationshipsBlockedByListViewQuery
    lazyRelationshipsBlockingListViewQuery: LazyRelationshipsBlockingListViewQuery
  }>(
    () => (
      <ThemeProvider>
        <Suspense fallback="Loading...">{lazyComponent}</Suspense>
      </ThemeProvider>
    ),
    {
      relay: {
        queries: {
          lazyRelationshipsBlockedByListViewQuery: {
            type: 'lazy',
          },
          lazyRelationshipsBlockingListViewQuery: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          Repository({path}) {
            return resolveByPath(mockedResponse, path)
          },
          Issue({path}) {
            return resolveByPath(mockedResponse, path)
          },
          PageInfo({path}) {
            return resolveByPath(mockedResponse, path)
          },
        },
      },
    },
  )

  return {environment: relayMockEnvironment}
}

describe('LazyRelationshipsBlockedByListView', () => {
  test('renders blockedBy private issues notice when blockedByCount is greater than visibleIssues', async () => {
    const issues = [
      {
        title: 'Issue 1',
        number: 1,
        repository: {
          nameWithOwner: 'other-user/other-repo',
        },
      },
    ]
    const props = {itemId: 'I_0001', visibleIssues: 1, blockedByCount: 3}
    setup('blockedBy', issues, <LazyRelationshipsBlockedByListView {...props} />)

    const notice = await screen.findByTestId('private-blocked-by-notice-modal')
    expect(notice).toBeInTheDocument()
    expect(notice).toHaveTextContent('Private issues are hidden')
  })

  test('does not render blockedBy private issues notice when blockedByCount is the same as visibleIssues', async () => {
    const issues = [
      {
        title: 'Issue 1',
        number: 1,
        repository: {
          nameWithOwner: 'other-user/other-repo',
        },
      },
    ]
    const props = {itemId: 'I_0001', visibleIssues: 1, blockedByCount: 1}
    setup('blockedBy', issues, <LazyRelationshipsBlockedByListView {...props} />)

    expect(screen.queryByTestId('private-blocked-by-notice-modal')).not.toBeInTheDocument()
  })

  test('renders blockedBy issues in the list view', async () => {
    const issues = [
      {title: 'Issue 1'},
      {title: 'Issue 2'},
      {
        title: 'Issue 3',
        number: 3,
        repository: {
          nameWithOwner: 'other-user/other-repo',
        },
      },
    ]
    const expectedReferences = ['#1', '#2', 'other-user/other-repo#3']

    const props = {itemId: 'I_0001', totalItems: issues.length, blockedByCount: issues.length}
    setup('blockedBy', issues, <LazyRelationshipsBlockedByListView {...props} />)

    // titles
    const listItemTitleElements = screen.getAllByTestId('list-view-item-title')
    expect(listItemTitleElements.length).toBe(issues.length)

    for (let i = 0; i < listItemTitleElements.length; i += 1) {
      const listItemElement = listItemTitleElements[i]
      const expectedTitle = issues[i]?.title

      expect(listItemElement).toHaveTextContent(expectedTitle!)
      expect(listItemElement).toBeInTheDocument()
    }

    // canonical references
    const descriptionElements = screen.getAllByTestId('list-view-item-description')
    expect(descriptionElements.length).toBe(expectedReferences.length)

    for (let i = 0; i < descriptionElements.length; i += 1) {
      const descriptionElement = descriptionElements[i]
      const expectedReference = expectedReferences[i]

      expect(descriptionElement).toHaveTextContent(expectedReference!)
      expect(descriptionElement).toBeInTheDocument()
    }
  })

  test('renders an empty state if there are no blockedBy issues associated with the parent issue', async () => {
    const props = {itemId: 'I_0001', blockedByCount: 0}
    setup('blockedBy', [], <LazyRelationshipsBlockedByListView {...props} />)

    const titleElements = screen.queryAllByTestId('list-view-item-title')
    expect(titleElements.length).toBe(0)

    expect(await screen.findByText(LABELS.emptyBlockedByList)).toBeInTheDocument()
  })

  test('loads the next page when loadMore is requested', async () => {
    const relayEnv = createMockEnvironment()

    render(
      <RelayEnvironmentProvider environment={relayEnv}>
        <Suspense fallback="Loading...">
          <LazyRelationshipsBlockedByListView itemId="I_999" pageSize={2} blockedByCount={4} />
        </Suspense>
      </RelayEnvironmentProvider>,
    )

    // resolving first page
    const firstPageIssues = [
      {number: 1, title: 'first page Issue 1'},
      {number: 2, title: 'first page Issue 2'},
    ]
    const firstPageResponse = generateMock('issue', 'blockedBy', firstPageIssues, {hasNextPage: true})
    act(() => {
      relayEnv.mock.resolveMostRecentOperation(operation =>
        MockPayloadGenerator.generate(operation, {
          Repository({path}) {
            return resolveByPath(firstPageResponse, path)
          },
          Issue({path}) {
            return resolveByPath(firstPageResponse, path)
          },
          PageInfo({path}) {
            return resolveByPath(firstPageResponse, path)
          },
        }),
      )
    })

    const button = await screen.findByRole('button', {name: LABELS.loadMoreItems})
    expect(button).not.toHaveAttribute('disabled')

    // check items
    const listItemTitleElements = screen.getAllByTestId('list-view-item-title')
    expect(listItemTitleElements.length).toBe(firstPageIssues.length)

    for (let i = 0; i < listItemTitleElements.length; i += 1) {
      const listItemElement = listItemTitleElements[i]
      const expectedTitle = firstPageIssues[i]?.title

      expect(listItemElement).toHaveTextContent(expectedTitle!)
      expect(listItemElement).toBeInTheDocument()
    }

    const secondPageIssues = [{number: 3, title: 'second page Issue 3'}]
    const secondPageResponse = generateMock('node', 'blockedBy', secondPageIssues, {hasNextPage: false})
    act(() => {
      button.click()

      relayEnv.mock.resolveMostRecentOperation(operation =>
        MockPayloadGenerator.generate(operation, {
          Repository({path}) {
            return resolveByPath(secondPageResponse, path)
          },
          Issue({path}) {
            return resolveByPath(secondPageResponse, path)
          },
          PageInfo({path}) {
            return resolveByPath(secondPageResponse, path)
          },
        }),
      )
    })

    expect(screen.queryByRole('button', {name: LABELS.loadMoreItems})).toBeNull()

    // check items
    const allIssues = [...firstPageIssues, ...secondPageIssues]
    const allListItemTitleElements = screen.getAllByTestId('list-view-item-title')
    expect(allListItemTitleElements.length).toBe(allIssues.length)

    for (let i = 0; i < allListItemTitleElements.length; i += 1) {
      const listItemElement = allListItemTitleElements[i]
      const expectedTitle = allIssues[i]?.title

      expect(listItemElement).toHaveTextContent(expectedTitle!)
      expect(listItemElement).toBeInTheDocument()
    }
  })
})

describe('LazyRelationshipsBlockingListView', () => {
  test('renders blocking private issues notice when blockingCount is greater than visibleIssues', async () => {
    const issues = [
      {
        title: 'Issue 1',
        number: 1,
        repository: {
          nameWithOwner: 'other-user/other-repo',
        },
      },
    ]
    const props = {itemId: 'I_0001', visibleIssues: 1, blockingCount: 3}
    setup('blocking', issues, <LazyRelationshipsBlockingListView {...props} />)

    const notice = await screen.findByTestId('private-blocking-notice-modal')
    expect(notice).toBeInTheDocument()
    expect(notice).toHaveTextContent('Private issues are hidden')
  })

  test('does not render blocking private issues notice when blockingCount is the same as visibleIssues', async () => {
    const issues = [
      {
        title: 'Issue 1',
        number: 1,
        repository: {
          nameWithOwner: 'other-user/other-repo',
        },
      },
    ]
    const props = {itemId: 'I_0001', visibleIssues: 1, blockingCount: 1}
    setup('blocking', issues, <LazyRelationshipsBlockingListView {...props} />)

    expect(screen.queryByTestId('private-blocking-notice-modal')).not.toBeInTheDocument()
  })

  test('renders blocking issues in the list view', async () => {
    const issues = [
      {title: 'Issue 1'},
      {title: 'Issue 2'},
      {
        title: 'Issue 3',
        number: 3,
        repository: {
          nameWithOwner: 'other-user/other-repo',
        },
      },
    ]
    const expectedReferences = ['#1', '#2', 'other-user/other-repo#3']

    const props = {itemId: 'I_0001', totalItems: issues.length, blockingCount: issues.length}
    setup('blocking', issues, <LazyRelationshipsBlockingListView {...props} />)

    // titles
    const listItemTitleElements = screen.getAllByTestId('list-view-item-title')
    expect(listItemTitleElements.length).toBe(issues.length)

    for (let i = 0; i < listItemTitleElements.length; i += 1) {
      const listItemElement = listItemTitleElements[i]
      const expectedTitle = issues[i]?.title

      expect(listItemElement).toHaveTextContent(expectedTitle!)
      expect(listItemElement).toBeInTheDocument()
    }

    // canonical references
    const descriptionElements = screen.getAllByTestId('list-view-item-description')
    expect(descriptionElements.length).toBe(expectedReferences.length)

    for (let i = 0; i < descriptionElements.length; i += 1) {
      const descriptionElement = descriptionElements[i]
      const expectedReference = expectedReferences[i]

      expect(descriptionElement).toHaveTextContent(expectedReference!)
      expect(descriptionElement).toBeInTheDocument()
    }
  })

  test('renders an empty state if there are no blocking issues associated with the parent issue', async () => {
    const props = {itemId: 'I_0001', totalItems: 0, blockingCount: 0}
    setup('blocking', [], <LazyRelationshipsBlockingListView {...props} />)

    const titleElements = screen.queryAllByTestId('list-view-item-title')
    expect(titleElements.length).toBe(0)

    expect(await screen.findByText(LABELS.emptyBlockingList)).toBeInTheDocument()
  })

  test('loads the next page when loadMore is requested', async () => {
    const relayEnv = createMockEnvironment()

    render(
      <RelayEnvironmentProvider environment={relayEnv}>
        <Suspense fallback="Loading...">
          <LazyRelationshipsBlockingListView itemId="I_999" pageSize={2} blockingCount={4} />
        </Suspense>
      </RelayEnvironmentProvider>,
    )

    // resolving first page
    const firstPageIssues = [
      {number: 1, title: 'first page Issue 1'},
      {number: 2, title: 'first page Issue 2'},
    ]
    const firstPageResponse = generateMock('issue', 'blocking', firstPageIssues, {hasNextPage: true})
    act(() => {
      relayEnv.mock.resolveMostRecentOperation(operation =>
        MockPayloadGenerator.generate(operation, {
          Repository({path}) {
            return resolveByPath(firstPageResponse, path)
          },
          Issue({path}) {
            return resolveByPath(firstPageResponse, path)
          },
          PageInfo({path}) {
            return resolveByPath(firstPageResponse, path)
          },
        }),
      )
    })

    const button = await screen.findByRole('button', {name: LABELS.loadMoreItems})
    expect(button).not.toHaveAttribute('disabled')

    // check items
    const listItemTitleElements = screen.getAllByTestId('list-view-item-title')
    expect(listItemTitleElements.length).toBe(firstPageIssues.length)

    for (let i = 0; i < listItemTitleElements.length; i += 1) {
      const listItemElement = listItemTitleElements[i]
      const expectedTitle = firstPageIssues[i]?.title

      expect(listItemElement).toHaveTextContent(expectedTitle!)
      expect(listItemElement).toBeInTheDocument()
    }

    const secondPageIssues = [{number: 3, title: 'second page Issue 3'}]
    const secondPageResponse = generateMock('node', 'blocking', secondPageIssues, {hasNextPage: false})
    act(() => {
      button.click()

      relayEnv.mock.resolveMostRecentOperation(operation =>
        MockPayloadGenerator.generate(operation, {
          Repository({path}) {
            return resolveByPath(secondPageResponse, path)
          },
          Issue({path}) {
            return resolveByPath(secondPageResponse, path)
          },
          PageInfo({path}) {
            return resolveByPath(secondPageResponse, path)
          },
        }),
      )
    })

    expect(screen.queryByRole('button', {name: LABELS.loadMoreItems})).toBeNull()

    // check items
    const allIssues = [...firstPageIssues, ...secondPageIssues]
    const allListItemTitleElements = screen.getAllByTestId('list-view-item-title')
    expect(allListItemTitleElements.length).toBe(allIssues.length)

    for (let i = 0; i < allListItemTitleElements.length; i += 1) {
      const listItemElement = allListItemTitleElements[i]
      const expectedTitle = allIssues[i]?.title

      expect(listItemElement).toHaveTextContent(expectedTitle!)
      expect(listItemElement).toBeInTheDocument()
    }
  })
})

const resolveByPath = (mockData: Record<string, unknown>, paths: readonly string[] | null | undefined) => {
  if (!paths) return {}

  let pathData = mockData
  for (const pathPart of paths) {
    if (!pathData || !pathData.hasOwnProperty(pathPart)) return {}
    pathData = pathData[pathPart] as Record<string, unknown>
  }
  return pathData
}

const generateMock = (
  returnNode: string,
  relationType: string,
  issues: Array<Record<string, unknown>>,
  pageInfo: Record<string, unknown> | null = null,
) => {
  const relationshipIssues: Array<Record<string, unknown>> = []
  const mockedResponse = {
    [returnNode]: {
      repository: {
        nameWithOwner: defaultTestRepository,
      },
      [relationType]: {
        edges: relationshipIssues,
        pageInfo: pageInfo || {
          hasNextPage: false,
          endCursor: null,
        },
      },
    },
  }

  let issueNumber = 1
  for (const issue of issues) {
    if (!issue.number) {
      issue.number = issueNumber
      issueNumber += 1
    }
    relationshipIssues.push({node: generateMockIssue(issue)})
  }

  return mockedResponse
}

let currentMockIssueId = 1
const generateMockIssue = (issue: Record<string, unknown>, repositoryNameWithOwner: string = defaultTestRepository) => {
  if (!issue.title) throw Error('Title is required to generate an issue mock')

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

  return issue
}
