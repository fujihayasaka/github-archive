/**
 * NOTE: Do not add any more tests to this file. New tests for `SearchBar` should be added t o `ui/packages/issues-react/components/search/__tests__/SearchBarWithFilter.test.tsx` file.
 * These tests `QueryBuilder` component which is being replaced with the `Filter` component.
 * This file will be deleted soon.
 */

import {expectAnalyticsEvents} from '@github-ui/analytics-test-utils'
import {render} from '@github-ui/react-core/test-utils'
// necessary import process to mock useAppPayload functionality
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import {screen, waitFor, act} from '@testing-library/react'
import {graphql, useLazyLoadQuery} from 'react-relay'
import type {OperationDescriptor} from 'relay-runtime'
import {createMockEnvironment, MockPayloadGenerator, type MockEnvironment} from 'relay-test-utils'

import {useQueryContext, useQueryEditContext} from '../../../contexts/QueryContext'
import HyperlistAppWrapper from '../../../test-utils/HyperlistAppWrapper'
import {buildSearchShortcut} from '../../../test-utils/IssueTestUtils'
import type {HyperlistTargetType} from '../../../types/analytics-event-types'
import {DashboardEditViewActions} from '../DashboardEditViewActions'
import type {DashboardEditViewActionsFragment$key} from '../__generated__/DashboardEditViewActionsFragment.graphql'
import {useEffect} from 'react'

// A clever way to check hook values without needing to mock more providers
let capturedHookValues: {
  queryContext: ReturnType<typeof useQueryContext>
  queryEditContext: ReturnType<typeof useQueryEditContext>
}

jest.mock('@github-ui/react-core/use-app-payload')
const mockedUseAppPayload = jest.mocked(useAppPayload)

beforeEach(() => {
  jest.clearAllMocks()

  capturedHookValues = {
    queryContext: {} as unknown as ReturnType<typeof useQueryContext>,
    queryEditContext: {} as unknown as ReturnType<typeof useQueryEditContext>,
  }
})

interface TestComponentProps {
  editMode?: boolean
  environment: ReturnType<typeof createMockEnvironment>
  activeQuery?: string
  newQuery?: string
}

function InnerTestComponent({editMode, activeQuery, newQuery}: Omit<TestComponentProps, 'environment'>) {
  const {isEditing, setIsEditing, setActiveSearchQuery} = useQueryContext()
  const {setDirtyTitle, setDirtySearchQuery} = useQueryEditContext()

  useEffect(() => {
    if (!isEditing && editMode) {
      setDirtyTitle('test')
      if (activeQuery) setActiveSearchQuery(activeQuery)
      if (newQuery) setDirtySearchQuery(newQuery)
      setIsEditing(true)
    }
  })

  const data = useLazyLoadQuery(
    graphql`
      query DashboardEditViewActionsQuery @relay_test_operation {
        node(id: "SSC_asdkasd") {
          # Spread the fragment you want to test here
          ...DashboardEditViewActionsFragment @dangerously_unaliased_fixme
        }
      }
    `,
    {},
  ) as {node: DashboardEditViewActionsFragment$key}

  return <DashboardEditViewActions currentView={data.node} />
}

// Add this component that will help expose the hook values
function HookValueCaptor() {
  // Get values from both hooks
  const queryContextValues = useQueryContext()
  const queryEditContextValues = useQueryEditContext()

  // Capture the values on each render
  useEffect(() => {
    capturedHookValues = {
      queryContext: {...queryContextValues},
      queryEditContext: {...queryEditContextValues},
    }
  })

  return null
}

function TestComponent({environment, activeQuery, ...inner}: TestComponentProps) {
  const searchQuery = activeQuery ?? 'is:issue state:open'
  return (
    <HyperlistAppWrapper environment={environment} metadata={{query: searchQuery}}>
      <>
        <HookValueCaptor />
        <InnerTestComponent activeQuery={searchQuery} {...inner} />
      </>
    </HyperlistAppWrapper>
  )
}

test('sends analytics event when query is saved', async () => {
  const activeQuery = 'repo:github/issues-react state:open'
  const newQuery = 'repo:github/issues-react state:closed'

  mockedUseAppPayload.mockReturnValue({
    initial_view_content: {},
    enabled_features: {},
  })
  const environment = createMockEnvironment()

  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      Node() {
        return buildSearchShortcut({query: activeQuery})
      },
    })
  })

  mockRepositoryQuery(environment)

  const {user} = render(
    <TestComponent editMode environment={environment} activeQuery={activeQuery} newQuery={newQuery} />,
  )

  const saveButton = await screen.findByText('Save view')

  await user.click(saveButton)

  expectAnalyticsEvents<HyperlistTargetType>({
    type: 'search.save',
    target: 'FILTER_BAR_SAVE_BUTTON',
    data: {
      app_name: 'hyperlist',
      query: activeQuery,
      new_query: newQuery,
    },
  })
})

test('clicking cancel button resets hook values correctly', async () => {
  const activeQuery = 'repo:github/issues-react state:open'
  const newQuery = 'repo:github/issues-react state:closed'

  mockedUseAppPayload.mockReturnValue({
    initial_view_content: {},
    enabled_features: {},
  })
  const environment = createMockEnvironment()

  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      Node() {
        return buildSearchShortcut({
          query: activeQuery,
        })
      },
    })
  })

  mockRepositoryQuery(environment)

  // Render with our hook value capturer
  const {user} = render(<TestComponent environment={environment} activeQuery={activeQuery} newQuery={newQuery} />)

  act(() => {
    capturedHookValues.queryContext.setIsEditing(true)
  })

  // Capture values before clicking cancel
  const beforeCancel = {
    isEditing: capturedHookValues.queryContext.isEditing,
    dirtyTitle: capturedHookValues.queryEditContext.dirtyTitle,
    dirtySearchQuery: capturedHookValues.queryEditContext.dirtySearchQuery,
  }

  // Verify we're in edit mode with dirty values
  expect(beforeCancel.isEditing).toBe(true)

  // Find and click the cancel button
  const cancelButton = await screen.findByText('Cancel')

  await user.click(cancelButton)

  // Wait for state updates to be reflected
  await waitFor(() => {
    expect(capturedHookValues.queryContext.isEditing).toBe(false)
  })
})

function mockRepositoryQuery(environment: MockEnvironment, isEnterpriseManaged = false) {
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {name: 'test-repo-name', owner: 'test-repo-owner', isOwnerEnterpriseManaged: isEnterpriseManaged}
      },
    })
  })
}
