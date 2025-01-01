import {Wrapper} from '@github-ui/react-core/test-utils'
import {act, screen} from '@testing-library/react'

import {
  DefaultMilestonePickerAnchor,
  MilestonePicker,
  MilestonePickerSearchGraphqlQuery,
  type Milestone,
  type MilestonePickerProps,
} from '../components/MilestonePicker'
import {noop} from '@github-ui/noop'
import {renderRelay} from '@github-ui/relay-test-utils'
import {MockPayloadGenerator, createMockEnvironment} from 'relay-test-utils'
import type {OperationDescriptor} from 'relay-runtime'
import {VALUES} from '../constants/values'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {withDisabledCharacterKeys} from '@github-ui/ui-commands/test-utils'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'

test('open picker via click', async () => {
  const {user} = renderRelay(
    () => {
      const sharedProps = {
        activeMilestone: null,
      } as MilestonePickerProps

      return (
        <MilestonePicker
          {...sharedProps}
          repo="github"
          owner="issues"
          readonly={false}
          onSelectionChanged={noop}
          anchorElement={props => <DefaultMilestonePickerAnchor anchorProps={props} {...sharedProps} />}
        />
      )
    },
    {
      relay: {
        queries: {
          recentMilestones: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          Repository: () => ({
            milestones: {
              nodes: Array(2).fill(undefined),
            },
          }),
        },
      },
      wrapper: Wrapper,
    },
  )

  await user.click(screen.getByRole('button', {name: 'Select milestone'}))

  expect(screen.getByRole('heading', {name: 'Set milestone'})).toBeInTheDocument()
  expect(screen.getByRole('textbox', {name: 'Filter milestones'})).toBeInTheDocument()

  const milestones = screen.getAllByRole('option')
  expect(milestones).toHaveLength(2)
})

test('open picker via keyboard when shortcutEnabled is true', async () => {
  const {user} = renderRelay(
    () => {
      const sharedProps = {
        activeMilestone: null,
      } as MilestonePickerProps

      return (
        <MilestonePicker
          {...sharedProps}
          repo="github"
          owner="issues"
          readonly={false}
          onSelectionChanged={noop}
          anchorElement={props => <DefaultMilestonePickerAnchor anchorProps={props} {...sharedProps} />}
        />
      )
    },
    {
      relay: {
        queries: {
          recentMilestones: {
            type: 'lazy',
          },
        },
      },
      wrapper: Wrapper,
    },
  )

  expect(screen.queryByText('Set milestone')).not.toBeInTheDocument()

  await user.keyboard('m')

  expect(screen.getByText('Set milestone')).toBeInTheDocument()
})

test('selecting a milestone is calling the onSelectionChanged callback', async () => {
  const onSelectionChangeMock = jest.fn()
  const {user} = renderRelay(
    () => {
      const sharedProps = {
        activeMilestone: null,
      } as MilestonePickerProps

      return (
        <MilestonePicker
          {...sharedProps}
          repo="github"
          owner="issues"
          readonly={false}
          onSelectionChanged={onSelectionChangeMock}
          anchorElement={props => <DefaultMilestonePickerAnchor anchorProps={props} {...sharedProps} />}
        />
      )
    },
    {
      relay: {
        queries: {
          recentMilestones: {
            type: 'lazy',
          },
        },
      },
      wrapper: Wrapper,
    },
  )

  await user.keyboard('m')

  const milestones = screen.getAllByRole('option')
  const firstMilestone = milestones[0]!

  await user.click(firstMilestone)

  expect(onSelectionChangeMock).toHaveBeenNthCalledWith(1, [
    expect.objectContaining({title: firstMilestone.textContent}),
  ])
})

test('do not open picker via keyboard when shortcutEnabled is false', async () => {
  await withDisabledCharacterKeys(async () => {
    const {user} = renderRelay(
      () => {
        const sharedProps = {
          activeMilestone: null,
        } as MilestonePickerProps

        return (
          <MilestonePicker
            {...sharedProps}
            repo="github"
            owner="issues"
            readonly={false}
            onSelectionChanged={noop}
            anchorElement={props => <DefaultMilestonePickerAnchor anchorProps={props} {...sharedProps} />}
          />
        )
      },
      {
        relay: {
          queries: {
            recentMilestones: {
              type: 'lazy',
            },
          },
        },
        wrapper: Wrapper,
      },
    )

    await user.keyboard('m')

    expect(screen.queryByText('Set milestone')).not.toBeInTheDocument()
  })
})

test('server request searching', async () => {
  const environment = createMockEnvironment()
  const owner = 'github'
  const repo = 'issues'
  const milestoneA = {id: mockRelayId(), title: 'milestone A'} as Milestone
  const milestoneB = {id: mockRelayId(), title: 'milestone B'} as Milestone
  const {user} = renderRelay(
    () => {
      const sharedProps = {
        activeMilestone: null,
      } as MilestonePickerProps

      return (
        <MilestonePicker
          {...sharedProps}
          owner={owner}
          repo={repo}
          readonly={false}
          onSelectionChanged={noop}
          anchorElement={props => <DefaultMilestonePickerAnchor anchorProps={props} {...sharedProps} />}
        />
      )
    },
    {
      relay: {
        queries: {
          recentMilestones: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          Repository: () => ({
            milestones: {
              nodes: [milestoneA, milestoneB],
            },
          }),
        },
        environment,
      },
      wrapper: Wrapper,
    },
  )

  await user.keyboard('m')

  // Expect preloaded milestones
  expect(screen.getByText(milestoneA.title)).toBeInTheDocument()
  expect(screen.getByText(milestoneB.title)).toBeInTheDocument()

  // Type on the input, should be auto-focused
  const filterInput = screen.getByRole('textbox', {name: 'Filter milestones'})
  expect(filterInput).toHaveFocus()

  await user.type(filterInput, 'give me my mocked milestones')

  act(() => {
    // Mock search request
    environment.mock.queuePendingOperation(MilestonePickerSearchGraphqlQuery, {
      query: 'give me my mocked milestones',
      owner,
      repo,
      count: 10,
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) =>
      MockPayloadGenerator.generate(operation, {
        Repository: () => ({
          milestones: {
            nodes: [{title: 'Cool mocked milestone'}],
          },
        }),
      }),
    )
  })

  // Expect filtered milestone only, async required due to debounce
  await screen.findByText('Cool mocked milestone', undefined, {timeout: VALUES.pickerDebounceTime + 100})
  expect(screen.queryByText('milestone A')).not.toBeInTheDocument()
  expect(screen.queryByText('milestone B')).not.toBeInTheDocument()
})

test('shows the correct milestone description', async () => {
  const environment = createMockEnvironment()
  const owner = 'github'
  const repo = 'issues'

  const previousDateDateTime = () => {
    const date = new Date()
    date.setDate(date.getDate() - 2)
    return date.toISOString()
  }

  const futureDateDateTime = () => {
    const date = new Date()
    date.setDate(date.getDate() + 2)
    return date.toISOString()
  }

  const previousDate = previousDateDateTime()
  const futureDate = futureDateDateTime()

  const {user} = renderRelay(
    () => {
      const sharedProps = {
        activeMilestone: null,
      } as MilestonePickerProps

      return (
        <MilestonePicker
          {...sharedProps}
          owner={owner}
          repo={repo}
          readonly={false}
          onSelectionChanged={noop}
          anchorElement={props => <DefaultMilestonePickerAnchor anchorProps={props} {...sharedProps} />}
          showMilestoneDescription
        />
      )
    },
    {
      relay: {
        queries: {
          recentMilestones: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          Repository: () => ({
            milestones: {
              nodes: [
                {title: 'milestone A', dueOn: previousDate, closed: false},
                {title: 'milestone B', dueOn: futureDate, closed: false},
                {title: 'milestone C', closed: false},
                {title: 'milestone D', closed: true, closedAt: previousDate},
              ],
            },
          }),
        },
        environment,
      },
      wrapper: Wrapper,
    },
  )

  await user.keyboard('m')

  // eslint-disable-next-line testing-library/no-node-access
  const previousRelativeTime = document.querySelector(`[datetime="${previousDate}"]`)

  // Expect preloaded milestones
  expect(screen.getByText('Past due by')).toBeInTheDocument()
  expect(screen.getByText(/Due\s+by\s+/)).toBeInTheDocument()
  expect(screen.getByText('No due date')).toBeInTheDocument()
  // these are two as we have a section that shows the closed milestones titled `Closed`
  expect(screen.getAllByText('Closed').length).toBe(2)

  expect(previousRelativeTime).toBeInTheDocument()
})

test('does not clear the selection if selected item is filtered out', async () => {
  const environment = createMockEnvironment()
  const owner = 'github'
  const repo = 'issues'
  const onSelectionChangeMock = jest.fn()
  const milestone = {id: mockRelayId(), title: 'milestone A'} as Milestone
  const {user} = renderRelay(
    () => {
      const sharedProps = {
        shortcutEnabled: true,
      } as MilestonePickerProps

      return (
        <MilestonePicker
          {...sharedProps}
          owner={owner}
          repo={repo}
          readonly={false}
          onSelectionChanged={onSelectionChangeMock}
          activeMilestone={milestone}
          anchorElement={props => <DefaultMilestonePickerAnchor anchorProps={props} {...sharedProps} />}
        />
      )
    },
    {
      relay: {
        queries: {
          recentMilestones: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          Repository: () => ({
            milestones: {
              nodes: [milestone],
            },
          }),
        },
        environment,
      },
      wrapper: Wrapper,
    },
  )

  await user.keyboard('m')

  // Expect preloaded milestones
  expect(screen.getByText('milestone A')).toBeInTheDocument()

  // Type on the input, should be auto-focused
  const filterInput = screen.getByRole('textbox', {name: 'Filter milestones'})
  expect(filterInput).toHaveFocus()

  await act(async () => {
    await user.type(filterInput, 'ZZ')
  })

  await act(async () => {
    // Mock search request
    environment.mock.queuePendingOperation(MilestonePickerSearchGraphqlQuery, {
      query: 'ZZ',
      owner,
      repo,
      count: 10,
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) =>
      MockPayloadGenerator.generate(operation, {
        Repository: () => ({
          milestones: {
            nodes: [{title: 'Cool mocked milestone'}],
          },
        }),
      }),
    )
  })

  await screen.findByText('Cool mocked milestone', undefined, {timeout: VALUES.pickerDebounceTime + 100})

  await user.keyboard('[Escape]')
  expect(onSelectionChangeMock).not.toHaveBeenCalled()
})

test('shows create new option if the milestone is not found, does nothing if not clicked', async () => {
  const environment = createMockEnvironment()
  const owner = 'github'
  const repo = 'issues'
  const onSelectionChangeMock = jest.fn()
  const milestone = {id: mockRelayId(), title: 'milestone A'} as Milestone
  const {user} = renderRelay(
    () => {
      const sharedProps = {
        shortcutEnabled: true,
      } as MilestonePickerProps

      return (
        <MilestonePicker
          {...sharedProps}
          owner={owner}
          repo={repo}
          readonly={false}
          onSelectionChanged={onSelectionChangeMock}
          activeMilestone={milestone}
          anchorElement={props => <DefaultMilestonePickerAnchor anchorProps={props} {...sharedProps} />}
          showNoMatchItem
        />
      )
    },
    {
      relay: {
        queries: {
          recentMilestones: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          Repository: () => ({
            milestones: {
              nodes: [milestone],
            },
          }),
        },
        environment,
      },
      wrapper: Wrapper,
    },
  )

  await user.keyboard('m')

  // Expect preloaded milestones
  expect(screen.getByText('milestone A')).toBeInTheDocument()

  // Type on the input, should be auto-focused
  const filterInput = screen.getByRole('textbox', {name: 'Filter milestones'})
  expect(filterInput).toHaveFocus()

  await act(async () => {
    await user.type(filterInput, 'ZZ')
  })

  await act(async () => {
    // Mock search request
    environment.mock.queuePendingOperation(MilestonePickerSearchGraphqlQuery, {
      query: 'ZZ',
      owner,
      repo,
      count: 10,
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) =>
      MockPayloadGenerator.generate(operation, {
        Repository: () => ({
          milestones: {
            nodes: [],
          },
        }),
      }),
    )
  })

  const createNewMilestoneLabel = await screen.findByText(/Create new milestone/, undefined, {
    timeout: VALUES.pickerDebounceTime + 100,
  })

  expect(createNewMilestoneLabel).toBeInTheDocument()
  await user.keyboard('[Escape]')
  expect(onSelectionChangeMock).not.toHaveBeenCalled()
})

test('shows create new option if the milestone is not found, fires the mutation when clicked', async () => {
  const {environment} = createRelayMockEnvironment()
  const owner = 'github'
  const repo = 'issues'
  const onSelectionChangeMock = jest.fn()
  let lastSelectedMilestones: Milestone[] = []
  onSelectionChangeMock.mockImplementation((selectedMilestones: Milestone[]) => {
    lastSelectedMilestones = selectedMilestones
  })
  const milestone = {id: mockRelayId(), title: 'milestone A'} as Milestone
  const {user} = renderRelay(
    () => {
      const sharedProps = {
        shortcutEnabled: true,
      } as MilestonePickerProps

      return (
        <MilestonePicker
          {...sharedProps}
          owner={owner}
          repo={repo}
          readonly={false}
          onSelectionChanged={onSelectionChangeMock}
          activeMilestone={milestone}
          anchorElement={props => <DefaultMilestonePickerAnchor anchorProps={props} {...sharedProps} />}
          showNoMatchItem
        />
      )
    },
    {
      relay: {
        queries: {
          recentMilestones: {
            type: 'lazy',
          },
        },
        mockResolvers: {
          Repository: () => ({
            milestones: {
              nodes: [milestone],
            },
            id: 'repository-id-3',
          }),
        },
        environment,
      },
      wrapper: Wrapper,
    },
  )

  await user.keyboard('m')

  // Expect preloaded milestones
  expect(screen.getByText('milestone A')).toBeInTheDocument()

  // Type on the input, should be auto-focused
  const filterInput = screen.getByRole('textbox', {name: 'Filter milestones'})
  expect(filterInput).toHaveFocus()

  await act(async () => {
    await user.type(filterInput, 'ZZ')
  })

  await act(async () => {
    // Mock search request
    environment.mock.queuePendingOperation(MilestonePickerSearchGraphqlQuery, {
      query: 'ZZ',
      owner,
      repo,
      count: 10,
    })
    environment.mock.queueOperationResolver((operation: OperationDescriptor) =>
      MockPayloadGenerator.generate(operation, {
        Repository: () => ({
          milestones: {
            nodes: [],
          },
        }),
      }),
    )
  })

  const createNewMilestoneLabel = await screen.findByText(/Create new milestone/, undefined, {
    timeout: VALUES.pickerDebounceTime + 100,
  })

  expect(createNewMilestoneLabel).toBeInTheDocument()

  await user.click(createNewMilestoneLabel)

  await act(async () => {
    environment.mock.resolveMostRecentOperation(operation => {
      expect(operation.request.node.params.name).toBe('createMilestoneMutation')
      expect(operation.fragment.variables).toEqual({
        input: {
          repositoryId: 'repository-id-3',
          title: 'ZZ',
        },
      })
      return MockPayloadGenerator.generate(operation, {
        Milestone() {
          return {
            closed: false,
            closedAt: null,
            dueOn: null,
            id: 'new-milestone-id',
            progressPercentage: 0,
            title: 'ZZ',
            url: '/github/issues/milestones/1',
          }
        },
      })
    })
  })

  await user.keyboard('[Escape]')

  expect(lastSelectedMilestones.at(-1)).toEqual({
    closed: false,
    closedAt: null,
    dueOn: null,
    id: 'new-milestone-id',
    progressPercentage: 0,
    title: 'ZZ',
    url: '/github/issues/milestones/1',
  })
})
