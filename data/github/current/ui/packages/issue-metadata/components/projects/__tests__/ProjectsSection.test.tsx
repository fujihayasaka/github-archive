import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {EditIssueProjectsSection} from '../ProjectsSection'
import {
  type OperationDescriptor,
  RelayEnvironmentProvider,
  useQueryLoader,
  usePreloadedQuery,
  type PreloadedQuery,
  graphql,
} from 'react-relay'
import {useEffect} from 'react'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'
import {ProjectPickerGraphqlQuery} from '@github-ui/item-picker/ProjectPicker'
import type {ProjectsSectionQuery} from './__generated__/ProjectsSectionQuery.graphql'
import {ERRORS} from '../../../constants/errors'

const ProjectsSectionGraphqlQuery = graphql`
  query ProjectsSectionQuery($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      issueOrPullRequest(number: $number) {
        ...ProjectsSectionFragment
      }
    }
  }
`

describe('Button conditional rendering for permissions', () => {
  // Mock issue identifier
  const owner = 'owner'
  const repo = 'repo'
  const number = 1

  const TestWrapper = () => {
    const [projectsRef, loadProjects, disposeProjects] =
      useQueryLoader<ProjectsSectionQuery>(ProjectsSectionGraphqlQuery)

    useEffect(() => {
      loadProjects({owner, repo, number})

      return () => {
        disposeProjects()
      }
    }, [disposeProjects, loadProjects])

    if (!projectsRef) return null

    return <TestInnerWrapper projectsRef={projectsRef} />
  }

  const TestInnerWrapper = ({projectsRef}: {projectsRef: PreloadedQuery<ProjectsSectionQuery>}) => {
    const data = usePreloadedQuery<ProjectsSectionQuery>(ProjectsSectionGraphqlQuery, projectsRef)

    if (!data.repository?.issueOrPullRequest) return null

    return (
      <EditIssueProjectsSection issueOrPullRequest={data.repository.issueOrPullRequest} singleKeyShortcutsEnabled />
    )
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const mockIssue = (environment: RelayMockEnvironment, overrides?: any, repositoryOverrides?: any) => {
    environment.mock.queuePendingOperation(ProjectsSectionGraphqlQuery, {owner, repo, number})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Repository() {
          return {
            id: 'repo_1',
            isArchived: false,
            issueOrPullRequest: {
              id: 'issue_1',
              projectItemsNext: {
                edges: [
                  {
                    node: {
                      id: 'project_item1',
                      project: {
                        title: 'Project 1',
                      },
                    },
                  },
                ],
                pageInfo: {
                  hasNextPage: false,
                  endCursor: 'd',
                },
              },
              viewerCanUpdateNext: true,
              ...overrides,
            },
            ...repositoryOverrides,
          }
        },
      })
    })
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const mockIssueWithoutProjects = (environment: RelayMockEnvironment, overrides?: any, repositoryOverrides?: any) => {
    environment.mock.queuePendingOperation(ProjectsSectionGraphqlQuery, {owner, repo, number})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      return MockPayloadGenerator.generate(operation, {
        Repository() {
          return {
            id: 'repo_1',
            isArchived: false,
            issueOrPullRequest: {
              id: 'issue_1',
              projectItemsNext: null,
              viewerCanUpdateNext: true,
              ...overrides,
            },
            ...repositoryOverrides,
          }
        },
      })
    })
  }

  const mockProjects = (environment: RelayMockEnvironment) => {
    environment.mock.queuePendingOperation(ProjectPickerGraphqlQuery, {owner, repo})
    environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
      expect(operation.fragment.node.name).toBe('ProjectPickerQuery')
      return MockPayloadGenerator.generate(operation, {
        Repository() {
          return {
            id: 'repo_1',
            projectsV2: {
              edges: [],
            },
            recentProjects: {
              edges: [],
            },
            owner: {
              projectsV2: {
                edges: [],
              },
              recentProjects: {
                edges: [],
              },
            },
          }
        },
      })
    })
  }

  test('renders fallback if project items are null', async () => {
    const environment = createMockEnvironment()
    mockIssueWithoutProjects(environment, {
      viewerCanUpdateNext: true,
    })

    render(
      <RelayEnvironmentProvider environment={environment}>
        <TestWrapper />
      </RelayEnvironmentProvider>,
    )

    expect(screen.getByText(ERRORS.projectsUnavailable)).toBeInTheDocument()
    expect(screen.getByText(ERRORS.tryAgainLater)).toBeInTheDocument()
  })

  test('renders edit button if user has update permissions', async () => {
    const environment = createMockEnvironment()
    mockIssue(environment, {
      viewerCanUpdateNext: true,
    })
    mockProjects(environment)

    render(
      <RelayEnvironmentProvider environment={environment}>
        <TestWrapper />
      </RelayEnvironmentProvider>,
    )

    expect(screen.getByText('Edit Projects')).toBeInTheDocument()
  })

  test('doesnt render edit button if user has no update permissions', async () => {
    const environment = createMockEnvironment()
    mockIssue(environment, {
      viewerCanUpdateMetadata: false,
    })
    mockProjects(environment)

    render(
      <RelayEnvironmentProvider environment={environment}>
        <TestWrapper />
      </RelayEnvironmentProvider>,
    )

    expect(screen.queryByText('Edit Projects')).not.toBeInTheDocument()
  })

  test('render project on a writable issue', async () => {
    const environment = createMockEnvironment()
    mockIssue(environment, {
      viewerCanUpdateNext: true,
    })
    mockProjects(environment)

    render(
      <RelayEnvironmentProvider environment={environment}>
        <TestWrapper />
      </RelayEnvironmentProvider>,
    )

    const section = screen.getByTestId('sidebar-projects-section')
    expect(section).toBeInTheDocument()
    expect(within(section).getByText('Project 1')).toBeVisible()
  })

  test('render project on a readonly issue', async () => {
    const environment = createMockEnvironment()
    mockIssue(environment, {
      viewerCanUpdateNext: false,
    })
    mockProjects(environment)

    render(
      <RelayEnvironmentProvider environment={environment}>
        <TestWrapper />
      </RelayEnvironmentProvider>,
    )

    const section = screen.getByTestId('sidebar-projects-section')
    expect(section).toBeInTheDocument()
    expect(within(section).getByText('Project 1')).toBeVisible()
  })

  test('doesnt render edit button if repository is archived', async () => {
    const environment = createMockEnvironment()
    mockIssue(environment, {}, {isArchived: true})
    mockProjects(environment)

    render(
      <RelayEnvironmentProvider environment={environment}>
        <TestWrapper />
      </RelayEnvironmentProvider>,
    )

    expect(screen.queryByText('Edit Projects')).not.toBeInTheDocument()
  })
})
