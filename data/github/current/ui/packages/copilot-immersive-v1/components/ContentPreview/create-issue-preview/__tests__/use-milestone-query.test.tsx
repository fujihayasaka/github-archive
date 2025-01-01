// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import type {Milestone} from '@github-ui/item-picker/MilestonePicker'
import {renderHook} from '@github-ui/react-core/test-utils'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {waitFor} from '@testing-library/react'
import {type OperationDescriptor, RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment, MockPayloadGenerator} from 'relay-test-utils'

import {useMilestoneQuery} from '../use-milestone-query'

const MILESTONES: Milestone[] = ['v1.0', 'v1.1', 'v2.0'].map(name => ({
  title: name,
  id: mockRelayId(),
  url: '',
  progressPercentage: 0,
  dueOn: '',
  closed: false,
  closedAt: '',
  ' $fragmentType': 'MilestonePickerMilestone',
}))

function setupEnvironment(result: Milestone | undefined) {
  const environment = createMockEnvironment()

  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    expect(operation.request.node.params.name).toBe('MilestonePickerSearchQuery')
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {
          milestones: {
            nodes: result ? [result] : [],
          },
        }
      },
    })
  })

  return environment
}

describe('useMilestonesQuery', () => {
  it('should return milestone', async () => {
    const milestone = MILESTONES[0]!
    const environment = setupEnvironment(milestone)
    const {result} = renderHook(
      () => useMilestoneQuery({owner: 'monalisa', repo: 'smile', milestone: milestone.title}),
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
          data: expect.objectContaining({
            id: milestone.id,
            title: milestone.title,
          }),
        }),
      )
    })
  })

  it('should return null when milestone is not found', async () => {
    const environment = setupEnvironment(undefined)
    const {result} = renderHook(() => useMilestoneQuery({owner: 'monalisa', repo: 'smile', milestone: 'v9.0'}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: null,
        }),
      )
    })
  })

  it('should return null when owner or repo is not provided', async () => {
    const environment = setupEnvironment(undefined)
    const {result} = renderHook(() => useMilestoneQuery({owner: undefined, repo: undefined, milestone: undefined}), {
      wrapper: ({children}) => (
        <RelayEnvironmentProvider environment={environment}>{children}</RelayEnvironmentProvider>
      ),
    })

    await waitFor(() => {
      expect(result.current).toEqual(
        expect.objectContaining({
          isLoading: false,
          isError: false,
          data: null,
        }),
      )
    })
  })

  it('should return loading state while query is loading', () => {
    const environment = setupEnvironment(undefined)
    const {result} = renderHook(() => useMilestoneQuery({owner: 'monalisa', repo: 'smile', milestone: 'v1.0'}), {
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
    const {result} = renderHook(() => useMilestoneQuery({owner: 'monalisa', repo: 'smile', milestone: 'v1.0'}), {
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
