import {render} from '@github-ui/react-core/test-utils'
import {fireEvent, screen, waitFor, act} from '@testing-library/react'
import type {OperationDescriptor} from 'relay-runtime'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'
import {LABELS} from '../constants/labels'

import {SearchRepositories, TopRepositories} from '../components/RepositoryPicker'
import {TestRepositoryPickerComponent, buildRepository} from '../test-utils/RepositoryPickerHelpers'
import type {RepositoryPickerRepository$data as Repository} from '../components/__generated__/RepositoryPickerRepository.graphql'

test('renders top repositories', async () => {
  const environment = createMockEnvironment()

  environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      RepositoryConnection() {
        return {
          edges: [
            {node: buildRepository({owner: 'orgA', name: 'repoA'})},
            {node: buildRepository({owner: 'orgA', name: 'repoB'})},
            {node: buildRepository({owner: 'orgB', name: 'repoC'})},
          ],
        }
      },
    })
  })

  render(<TestRepositoryPickerComponent environment={environment} />)

  const button = await screen.findByRole('button')
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('orgA/repoA')
  expect(options[1]).toHaveTextContent('orgA/repoB')
  expect(options[2]).toHaveTextContent('orgB/repoC')
})

test('renders top repositories and filter some out of the results', async () => {
  const environment = createMockEnvironment()

  environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      RepositoryConnection() {
        return {
          edges: [
            {node: buildRepository({owner: 'orgA', name: 'repoA'})},
            {node: buildRepository({owner: 'orgA', name: 'repoB'})},
            {node: buildRepository({owner: 'orgB', name: 'repoC'})},
          ],
        }
      },
    })
  })

  const repoFilter = (repo: Repository) => repo.name !== 'repoB'

  render(<TestRepositoryPickerComponent environment={environment} repositoryFilter={repoFilter} />)

  const button = await screen.findByRole('button')
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(2)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('orgA/repoA')
  expect(options[1]).toHaveTextContent('orgB/repoC')
})

test('all results get filtered out', async () => {
  const environment = createMockEnvironment()

  environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      RepositoryConnection() {
        return {
          edges: [
            {node: buildRepository({owner: 'orgA', name: 'repoA'})},
            {node: buildRepository({owner: 'orgA', name: 'repoB'})},
            {node: buildRepository({owner: 'orgA', name: 'repoC'})},
          ],
        }
      },
    })
  })

  const repoFilter = (repo: Repository) => repo.owner.login !== 'orgA'
  const customNoResultsText = 'custom_no_results_element'
  const customNoResultsItem = <div>{customNoResultsText}</div>

  render(
    <TestRepositoryPickerComponent
      environment={environment}
      repositoryFilter={repoFilter}
      customNoResultsItem={customNoResultsItem}
    />,
  )

  const button = await screen.findByRole('button')
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button)

  await waitFor(() => {
    expect(screen.getByText(customNoResultsText)).toBeDefined()
  })
})

test('renders repositories from known orgs first', async () => {
  const environment = createMockEnvironment()

  environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      RepositoryConnection() {
        return {
          edges: [{node: buildRepository({owner: 'orgA', name: 'top'})}],
        }
      },
    })
  })

  environment.mock.queuePendingOperation(SearchRepositories, {searchQuery: 'search in:name archived:false'})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      SearchResultItemConnection() {
        return {
          nodes: [
            buildRepository({owner: 'orgB', name: 'search1'}),
            buildRepository({owner: 'orgC', name: 'search2'}),
            buildRepository({owner: 'orgA', name: 'search3'}),
          ],
        }
      },
    })
  })

  const {user} = render(<TestRepositoryPickerComponent environment={environment} />)

  const button = await screen.findByRole('button')
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button)

  const input = await screen.findByPlaceholderText(LABELS.selectRepository)
  await user.type(input, 'search')
  fireEvent.submit(input)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })

  const options = await screen.findAllByRole('option')

  // orgA must be first because it was first seen in the top repositories query
  expect(options).toHaveLength(3)
  expect(options[0]).toHaveTextContent('orgA/search3')
  expect(options[1]).toHaveTextContent('orgB/search1')
  expect(options[2]).toHaveTextContent('orgC/search2')
})

test('renders top repositories including initial repository if not returned', async () => {
  const environment = createMockEnvironment()
  const initialRepository = {
    ...buildRepository({owner: 'userB', name: 'repoC'}),
    databaseId: null,
    slashCommandsEnabled: true,
    viewerIssueCreationPermissions: {
      assignable: true,
      labelable: true,
      milestneable: true,
      triageable: true,
      typeable: true,
    },
    $fragmentType: 'RepositoryPickerRepository',
  } as unknown as Repository

  environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      RepositoryConnection() {
        return {
          edges: [
            {node: buildRepository({owner: 'userA', name: 'repoA'})},
            {node: buildRepository({owner: 'userA', name: 'repoB'})},
          ],
        }
      },
    })
  })

  render(<TestRepositoryPickerComponent environment={environment} initialRepository={initialRepository} />)

  const button = await screen.findByRole('button')
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(3)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('userB/repoC')
  expect(options[1]).toHaveTextContent('userA/repoA')
  expect(options[2]).toHaveTextContent('userA/repoB')
})

test('renders top repositories not including initial repository if it belongs to a different organization', async () => {
  const environment = createMockEnvironment()
  const initialRepository = {
    ...buildRepository({owner: 'orgB', name: 'repoC'}),
    databaseId: null,
    slashCommandsEnabled: true,
    hasIssuesEnabled: true,
    viewerIssueCreationPermissions: {
      assignable: true,
      labelable: true,
      milestneable: true,
      triageable: true,
      typeable: true,
    },
    $fragmentType: 'RepositoryPickerRepository',
  } as unknown as Repository

  environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      RepositoryConnection() {
        return {
          edges: [
            {node: buildRepository({owner: 'orgA', name: 'repoA'})},
            {node: buildRepository({owner: 'orgA', name: 'repoB'})},
          ],
        }
      },
    })
  })

  render(
    <TestRepositoryPickerComponent
      environment={environment}
      initialRepository={initialRepository}
      organization="orgA"
    />,
  )

  const button = await screen.findByRole('button')
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(2)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('orgA/repoA')
  expect(options[1]).toHaveTextContent('orgA/repoB')
})

test('renders top repositories and excludes the passed `ignoredRepositories`', async () => {
  const environment = createMockEnvironment()

  environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      RepositoryConnection() {
        return {
          edges: [
            {node: buildRepository({owner: 'userA', name: 'repoA'})},
            {node: buildRepository({owner: 'userA', name: 'repoB'})},
            {node: buildRepository({owner: 'userA', name: 'excludedRepo'})},
          ],
        }
      },
    })
  })

  render(
    <TestRepositoryPickerComponent
      environment={environment}
      initialRepository={undefined}
      ignoredRepositories={['userA/excludedRepo']}
    />,
  )

  const button = await screen.findByRole('button')
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(2)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('userA/repoA')
  expect(options[1]).toHaveTextContent('userA/repoB')
  expect(screen.queryByText('userA/excludedRepo')).not.toBeInTheDocument()
})

test('excluded repositories are not shown in the search results', async () => {
  const environment = createMockEnvironment()

  environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      RepositoryConnection() {
        return {
          edges: [{node: buildRepository({owner: 'orgA', name: 'top'})}],
        }
      },
    })
  })

  environment.mock.queuePendingOperation(SearchRepositories, {searchQuery: 'search in:name archived:false'})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      SearchResultItemConnection() {
        return {
          nodes: [
            buildRepository({owner: 'orgB', name: 'search1'}),
            buildRepository({owner: 'orgA', name: 'search2'}),
            buildRepository({owner: 'orgA', name: 'search-excluded'}),
          ],
        }
      },
    })
  })

  const {user} = render(
    <TestRepositoryPickerComponent environment={environment} ignoredRepositories={['orgA/search-excluded']} />,
  )

  const button = await screen.findByRole('button')
  // eslint-disable-next-line testing-library/prefer-user-event
  fireEvent.click(button)

  const input = await screen.findByPlaceholderText(LABELS.selectRepository)
  await user.type(input, 'search')
  fireEvent.submit(input)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(2)
  })

  const options = await screen.findAllByRole('option')

  // orgA must be first because it was first seen in the top repositories query
  expect(options[0]).toHaveTextContent('orgA/search2')
  expect(options[1]).toHaveTextContent('orgB/search1')
  expect(screen.queryByText('userA/search-excluded')).not.toBeInTheDocument()
})

test('fetches possible transfer repositories when the issueId prop is provided (On issue transfer dialog)', async () => {
  const environment = createMockEnvironment()

  environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      RepositoryConnection() {
        return {
          edges: [
            {node: buildRepository({owner: 'orgA', name: 'top'})},
            {node: buildRepository({owner: 'orgA', name: 'top2'})},
          ],
        }
      },
    })
  })

  const {user} = render(<TestRepositoryPickerComponent environment={environment} issueId="random-id" />)

  const button = await screen.findByRole('button')

  user.click(button)

  const input = await screen.findByPlaceholderText(LABELS.selectRepository)
  await user.type(input, 'project')

  let fetchPossibleTransferReposQuery = environment.mock.getMostRecentOperation()

  // When the issueId is provided, we expect the possible transfer repositories query to be called
  await waitFor(() => {
    fetchPossibleTransferReposQuery = environment.mock.getMostRecentOperation()
    expect(fetchPossibleTransferReposQuery.fragment.node.name).toEqual(
      'RepositoryPickerPossibleTransferRepositoriesQuery',
    )
  })

  await waitFor(() => {
    fetchPossibleTransferReposQuery = environment.mock.getMostRecentOperation()
    expect(fetchPossibleTransferReposQuery.fragment.variables).toEqual({
      issueId: 'random-id',
      searchQuery: 'project',
    })
  })

  await act(async () => {
    environment.mock.resolveMostRecentOperation((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        RepositoryConnection() {
          return {
            edges: [
              {node: buildRepository({owner: 'orgA', name: 'project1'})},
              {node: buildRepository({owner: 'orgA', name: 'project2'})},
            ],
          }
        },
      })
    })
  })

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(2)
  })

  const options = await screen.findAllByRole('option')

  expect(options[0]).toHaveTextContent('orgA/project1')
  expect(options[1]).toHaveTextContent('orgA/project2')
})

describe('button label display', () => {
  const testRepository = {
    ...buildRepository({owner: 'orgA', name: 'testRepo'}),
    databaseId: null,
    slashCommandsEnabled: true,
    hasIssuesEnabled: true,
    viewerIssueCreationPermissions: {
      assignable: true,
      labelable: true,
      milestneable: true,
      triageable: true,
      typeable: true,
    },
    $fragmentType: 'RepositoryPickerRepository',
  } as unknown as Repository

  test('shows select repository label when no initial repository is provided', async () => {
    const noRepoEnvironment = createMockEnvironment()
    noRepoEnvironment.mock.queuePendingOperation(TopRepositories, {
      topRepositoriesFirst: 10,
      hasIssuesEnabled: true,
    })
    noRepoEnvironment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        RepositoryConnection() {
          return {
            edges: [],
          }
        },
      })
    })

    render(<TestRepositoryPickerComponent environment={noRepoEnvironment} initialRepository={undefined} />)

    const button = await screen.findByRole('button')
    expect(button).toHaveAttribute('aria-label', LABELS.selectRepository)
  })

  test('shows full repository name with owner when initial repository is provided', async () => {
    const environment = createMockEnvironment()
    environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        RepositoryConnection() {
          return {
            edges: [
              {node: buildRepository({owner: 'orgA', name: 'testRepo'})},
              {node: buildRepository({owner: 'orgA', name: 'testRepo2'})},
            ],
          }
        },
      })
    })

    render(<TestRepositoryPickerComponent environment={environment} initialRepository={testRepository} />)

    const button = await screen.findByRole('button')
    expect(button).toHaveAttribute('aria-label', 'Selected repository: orgA/testRepo')
  })

  test('shows repository name only when repoNameOnly prop is true', async () => {
    const environment = createMockEnvironment()
    environment.mock.queuePendingOperation(TopRepositories, {topRepositoriesFirst: 10, hasIssuesEnabled: true})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        RepositoryConnection() {
          return {
            edges: [
              {node: buildRepository({owner: 'orgA', name: 'testRepo'})},
              {node: buildRepository({owner: 'orgA', name: 'testRepo2'})},
            ],
          }
        },
      })
    })

    render(<TestRepositoryPickerComponent environment={environment} initialRepository={testRepository} repoNameOnly />)

    const button = await screen.findByRole('button')
    expect(button).toHaveAttribute('aria-label', 'Selected repository: testRepo')
  })
})
