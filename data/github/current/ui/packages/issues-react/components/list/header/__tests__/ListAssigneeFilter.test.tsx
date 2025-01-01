import {Wrapper} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {ListAssigneeFilter} from '../ListAssigneeFilter'
import {buildAssignee} from '@github-ui/item-picker/test-utils/AssigneePickerHelpers'
import {SPECIAL_VALUES} from '@github-ui/item-picker/Placeholders'
import {SearchAssignableRepositoryUsers} from '@github-ui/item-picker/AssigneePicker'
import {renderRelay} from '@github-ui/relay-test-utils'
import type {AssigneePickerSearchAssignableRepositoryUsersQuery} from '@github-ui/item-picker/AssigneePickerSearchAssignableRepositoryUsersQuery.graphql'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import {graphql} from 'relay-runtime'
import type {ListAssigneeFilterCurrentViewerTestQuery} from './__generated__/ListAssigneeFilterCurrentViewerTestQuery.graphql'
import {useFeatureFlags} from '@github-ui/react-core/use-feature-flag'

jest.mock('@github-ui/react-core/use-feature-flag')
const mockUseFeatureFlags = jest.mocked(useFeatureFlags)
mockUseFeatureFlags.mockReturnValue({})

const mockUseQueryContext = jest.fn()
const mockUseQueryEditContext = jest.fn()

jest.mock('../../../../contexts/QueryContext', () => ({
  useQueryContext: () => mockUseQueryContext({}),
  useQueryEditContext: () => mockUseQueryEditContext({}),
}))

beforeEach(() => {
  mockUseQueryContext.mockReturnValue({activeSearchQuery: '', currentViewId: 'repo'})
  mockUseQueryEditContext.mockReturnValue({debouncedDirtySearchQuery: 'dirty query not submitted yet'})
})

test('renders a menu with assignees', async () => {
  const {user} = renderListAssigneeFilter(() => {}, {})
  const button = screen.getByTestId('assignees-anchor-button')

  expect(button).toBeInTheDocument()
  expect(button.textContent).toBe('Assignees')
  expect(screen.queryByPlaceholderText('Filter assignees')).not.toBeInTheDocument()

  await user.click(button)
  const list = screen.queryByPlaceholderText('Filter assignees')

  expect(list).toBeInTheDocument()
  expect(list).toBeVisible()

  const listItems = screen.getAllByRole('option')

  expect(listItems.length).toBe(5)
  expect(listItems[0]).toHaveTextContent(SPECIAL_VALUES.noAssigneeData.login)
  expect(listItems[1]).toHaveTextContent('monalisaoctocat')
  expect(listItems[2]).toHaveTextContent('loginAnameA')
  expect(listItems[3]).toHaveTextContent('loginBnameB')
  expect(listItems[4]).toHaveTextContent('loginCnameC')
})

test('when selection is changed, it calls the provided callback', async () => {
  const callback = jest.fn()
  const {user} = renderListAssigneeFilter(callback, {})

  expect(callback).not.toHaveBeenCalled()

  const button = screen.getByTestId('assignees-anchor-button')
  await user.click(button)
  const list = screen.queryByLabelText('User results')

  expect(list).toBeInTheDocument()
  expect(list).toBeVisible()

  const listItems = screen.getAllByRole('option')

  expect(listItems[1]).toHaveTextContent('monalisaoctocat')

  await user.click(listItems[1]!)

  expect(list).not.toBeVisible()
  expect(callback).toHaveBeenCalledWith(
    'dirty query not submitted yet assignee:monalisa',
    '/issues/repo?q=dirty%20query%20not%20submitted%20yet%20assignee%3Amonalisa',
  )
})

test('correctly shows selected assignee and updates query on new selection', async () => {
  mockUseQueryEditContext.mockReturnValue({
    debouncedDirtySearchQuery: 'dirty query assignee:loginB',
  })

  const callback = jest.fn()
  const {user} = renderListAssigneeFilter(callback, {selectedAssignee: 'loginB'})
  const button = screen.getByTestId('assignees-anchor-button')

  expect(button).toBeInTheDocument()

  await user.click(button)
  const list = screen.queryByLabelText('User results')

  expect(list).toBeInTheDocument()
  expect(list).toBeVisible()
  expect(screen.getByRole('option', {selected: true})).toHaveTextContent('loginBnameB')

  const listItems = screen.getAllByRole('option')

  expect(listItems[2]).toHaveTextContent('monalisaoctocat')
  await user.click(listItems[2]!)

  expect(list).not.toBeVisible()
  expect(callback).toHaveBeenCalledWith(
    'dirty query assignee:monalisa',
    '/issues/repo?q=dirty%20query%20assignee%3Amonalisa',
  )
})

// For `ui/packages/item-picker/hooks/useViewer.tsx`
const _ = graphql`
  query ListAssigneeFilterCurrentViewerTestQuery {
    safeViewer {
      ...AssigneePickerAssignee
    }
  }
`

const renderListAssigneeFilter = (
  onSelectCallback: () => void,
  {selectedAssignee = undefined, query = null}: {selectedAssignee?: string; query?: string | null},
) => {
  type Queries = {
    fetchQuery: AssigneePickerSearchAssignableRepositoryUsersQuery
    currentViewerQuery: ListAssigneeFilterCurrentViewerTestQuery
  }

  const mockQueries: RelayMockProps<Queries> = {
    queries: {
      fetchQuery: {
        type: 'preloaded',
        query: SearchAssignableRepositoryUsers,
        variables: {
          owner: 'github',
          name: 'issues',
          query,
          loginNames: selectedAssignee,
          first: selectedAssignee ? 1 : 30,
          capabilities: ['CAN_BE_ASSIGNED'],
        },
      },
      currentViewerQuery: {
        type: 'lazy',
      },
    },
  }

  const assignees = [
    buildAssignee({login: 'loginA', name: 'nameA'}),
    buildAssignee({login: 'loginB', name: 'nameB'}),
    buildAssignee({login: 'loginC', name: 'nameC'}),
  ].filter(assignee => selectedAssignee === undefined || assignee.login === selectedAssignee)

  return renderRelay<Queries>(
    () => (
      <ListAssigneeFilter
        nested={false}
        repo={{name: 'issues', owner: 'github'}}
        applySectionFilter={onSelectCallback}
      />
    ),
    {
      relay: {
        ...mockQueries,
        mockResolvers: {
          Repository() {
            return {
              suggestedActors: {
                nodes: assignees,
                totalCount: assignees.length,
              },
            }
          },
          User() {
            {
              return {
                login: 'monalisa',
                name: 'octocat',
              }
            }
          },
        },
      },
      wrapper: Wrapper,
    },
  )
}
