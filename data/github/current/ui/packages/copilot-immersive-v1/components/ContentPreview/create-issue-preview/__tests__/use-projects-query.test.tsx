// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {renderHook} from '@github-ui/react-core/test-utils'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {waitFor} from '@testing-library/react'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {type Project, useProjectsQuery} from '../use-projects-query'

const PROJECTS: Project[] = ['Roadmap', 'Backlog'].map(name => ({
  title: name,
  id: mockRelayId(),
  number: 1,
  url: '',
  closed: false,
  hasReachedItemsLimit: false,
  viewerCanUpdate: true,
  __typename: 'ProjectV2',
  ' $fragmentType': 'ProjectPickerProject',
}))

function setupEnvironment(result: Project[] | undefined) {
  const environment = createMockEnvironment()

  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    expect(operation.request.node.params.name).toBe('ProjectPickerQuery')
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {
          projectsV2: {
            nodes: result ?? [],
          },
          recentProjects: {
            edges: result?.map(node => ({node})) ?? [],
          },
          owner: {
            projectsV2: {
              edges: result?.map(node => ({node})) ?? [],
            },
            recentProjects: {
              edges: result?.map(node => ({node})) ?? [],
            },
          },
        }
      },
    })
  })

  return environment
}

describe('useProjectsQuery', () => {
  it('should return projects', async () => {
    const environment = setupEnvironment(PROJECTS)
    const {result} = renderHook(
      () => useProjectsQuery({owner: 'monalisa', repo: 'smile', projects: PROJECTS.map(p => p.title)}),
      {
        wrapper: ({children}) => (
          <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
        ),
      },
    )

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: PROJECTS.map(node => {
            return expect.objectContaining({
              id: node.id,
              title: node.title,
            })
          }),
        }),
      )
    })
  })

  it('should return empty array when no projects are found', async () => {
    const environment = setupEnvironment([])
    const {result} = renderHook(
      () => useProjectsQuery({owner: 'monalisa', repo: 'smile', projects: ['Never Gonna Happen']}),
      {
        wrapper: ({children}) => (
          <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
        ),
      },
    )

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: [],
        }),
      )
    })
  })

  it('should return empty array when owner or repo is not provided', async () => {
    const environment = setupEnvironment([])
    const {result} = renderHook(() => useProjectsQuery({owner: undefined, repo: undefined, projects: []}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: [],
        }),
      )
    })
  })

  it('should return loading state while query is loading', () => {
    const environment = setupEnvironment([])
    const {result} = renderHook(() => useProjectsQuery({owner: 'monalisa', repo: 'smile', projects: []}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    // NOTE we are not using waitFor to finish here, so we stay in a loading state
    expect(result.current).toEqual(
      expect.objectContaining({
        isLoading: true,
        isError: false,
        data: undefined,
      }),
    )
  })

  it('should return error state when query fails', async () => {
    const environment = createMockEnvironment()
    const {result} = renderHook(() => useProjectsQuery({owner: 'monalisa', repo: 'smile', projects: ['Backlog']}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })
    environment.mock.rejectMostRecentOperation(new Error('Network error'))

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: true,
          data: undefined,
        }),
      )
    })
  })
})
