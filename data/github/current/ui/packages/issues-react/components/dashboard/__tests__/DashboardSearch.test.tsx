import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import {noop} from '@github-ui/noop'
import {renderRelay} from '@github-ui/relay-test-utils'
import {screen} from '@testing-library/react'
import {graphql} from 'react-relay'
import type {RelayMockEnvironment} from 'relay-test-utils/lib/RelayModernMockEnvironment'

import {TEST_IDS} from '../../../constants/test-ids'

import {DashboardSearch} from '../DashboardSearch'
import type {DashboardSearchTestQuery} from './__generated__/DashboardSearchTestQuery.graphql'
import type {DashboardSearchCurrentViewTestQuery} from './__generated__/DashboardSearchCurrentViewTestQuery.graphql'
import {Wrapper} from '@github-ui/react-core/test-utils'
import HyperlistAppWrapper from '../../../test-utils/HyperlistAppWrapper'
import {buildIssue} from '../../../test-utils/IssueTestUtils'
import {LABELS} from '../../../constants/labels'
import {useAppPayload} from '@github-ui/react-core/use-app-payload'
import type React from 'react'

// Mock QueryContext
const defaultQueryContextMocks = {
  canEditView: true,
  isEditing: false,
  isNewView: false,
  isCustomView: jest.fn().mockReturnValue(true),
}

const mockQueryContext = {
  ...defaultQueryContextMocks,
}

jest.mock('../../../contexts/QueryContext', () => {
  const originalModule = jest.requireActual('../../../contexts/QueryContext')

  return {
    ...originalModule,
    useQueryContext: () => {
      return {
        ...originalModule.useQueryContext(),
        ...mockQueryContext,
      }
    },
  }
})

jest.mock('@github-ui/react-core/use-app-payload')
const mockedUseAppPayload = jest.mocked(useAppPayload)

mockedUseAppPayload.mockReturnValue({
  initial_view_content: {},
  preloaded_records: [],
  enabled_features: {},
  current_user_settings: {use_single_key_shortcut: true},
  current_user: {
    avatarUrl: '',
    login: 'monalisa',
  },
})

beforeEach(() => {
  jest.clearAllMocks()

  Object.assign(mockQueryContext, defaultQueryContextMocks)
})

const LocalWrapper = ({children, environment}: {children: React.ReactNode; environment: RelayMockEnvironment}) => {
  return (
    <Wrapper>
      <HyperlistAppWrapper environment={environment}>{children as JSX.Element}</HyperlistAppWrapper>
    </Wrapper>
  )
}

function setup({query = '', isEditing = false, isNewView = false} = {}) {
  const {environment} = createRelayMockEnvironment()

  mockQueryContext.isEditing = isEditing
  mockQueryContext.isNewView = isNewView

  const {user} = renderRelay<{
    search: DashboardSearchTestQuery
    currentView: DashboardSearchCurrentViewTestQuery
  }>(
    ({queryData}) => (
      <DashboardSearch
        itemIdentifier={undefined}
        currentView={queryData.currentView.node!}
        search={queryData.search}
        loadSearchQuery={noop}
      />
    ),
    {
      relay: {
        queries: {
          search: {
            type: 'fragment',
            query: graphql`
              query DashboardSearchTestQuery(
                $query: String = ""
                $first: Int = 25
                $labelPageSize: Int = 20
                $skip: Int = null
              ) @relay_test_operation {
                ...DashboardSearchFragment
                  @arguments(
                    query: $query
                    first: $first
                    skip: $skip
                    labelPageSize: $labelPageSize
                    fetchRepository: true
                  )
              }
            `,
            variables: {
              query,
            },
          },
          currentView: {
            type: 'fragment',
            query: graphql`
              query DashboardSearchCurrentViewTestQuery @relay_test_operation {
                node(id: "view-id") {
                  ...DashboardSearchCurrentViewFragment @dangerously_unaliased_fixme
                }
              }
            `,
            variables: {},
          },
        },
        mockResolvers: {
          Node() {
            return {
              id: '123',
              name: 'Test View',
              description: 'Test Description',
              icon: 'bookmark',
              color: 'blue',
              query,
              scopingRepository: null,
            }
          },
          Searchable() {
            return {}
          },
          SearchResultItemConnection() {
            return {
              openIssueCount: 1,
              closedIssueCount: 2,
              edges: [{node: buildIssue({title: 'Test Issue'})}],
            }
          },
        },
        environment,
      },
      wrapper: ({children}) => {
        return <LocalWrapper environment={environment}>{children}</LocalWrapper>
      },
    },
  )

  return {environment, user}
}

describe('DashboardSearch', () => {
  test('renders search bar with the correct query', async () => {
    setup({
      query: 'is:issue state:open',
    })

    const input = await screen.findByTestId(TEST_IDS.searchWithFilterInput)
    expect(input).toBeInTheDocument()
    expect(input).toHaveValue('is:issue state:open ')
  })

  test('renders search results', async () => {
    setup()

    expect(await screen.findByText('Test Issue')).toBeInTheDocument()
  })

  test('renders NewViewExperience when isNewView is true and no activeSearchQuery', async () => {
    setup({isNewView: true})

    expect(
      await screen.findByRole('heading', {name: /Build powerful views to keep track of work/i}),
    ).toBeInTheDocument()
  })

  test('renders DashboardEditViewActions when isEditing is true', async () => {
    setup({isEditing: true})

    const saveButton = await screen.findByRole('button', {name: 'Save view'})
    const cancelButton = await screen.findByRole('button', {name: 'Cancel'})

    expect(saveButton).toBeInTheDocument()
    expect(cancelButton).toBeInTheDocument()
  })

  test('renders DashboardSearchBarActions when not editing', async () => {
    setup()

    const saveButton = await screen.findByRole('button', {name: 'Save'})
    expect(saveButton).toBeInTheDocument()
  })

  test('DashboardSearchBarActions save button is disabled by default', async () => {
    setup()

    const saveButton = await screen.findByRole('button', {name: 'Save'})
    expect(saveButton).toBeDisabled()
  })

  test('DashboardSearchBarActions save button is enabled when queryEditActive', async () => {
    const {user} = setup()

    const input = screen.getByRole('combobox', {name: LABELS.issueSearchInputAriaLabel})

    expect(input).not.toHaveFocus()
    await user.keyboard('{Control>}[Slash]{/Control}')
    expect(input).toHaveFocus()

    await user.type(input, 'extended query')

    const saveButton = await screen.findByRole('button', {name: 'Save'})
    expect(saveButton).not.toBeDisabled()
  })
})
