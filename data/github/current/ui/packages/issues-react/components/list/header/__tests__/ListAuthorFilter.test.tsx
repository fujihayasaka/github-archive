import {Wrapper} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {ListAuthorFilter} from '../ListAuthorFilter'
import {buildAssignee} from '@github-ui/item-picker/test-utils/AssigneePickerHelpers'
import {SearchAssignableRepositoryUsers} from '@github-ui/item-picker/AssigneePicker'
import {renderRelay} from '@github-ui/relay-test-utils'
import type {AssigneePickerSearchAssignableRepositoryUsersQuery} from '@github-ui/item-picker/AssigneePickerSearchAssignableRepositoryUsersQuery.graphql'
import type {RelayMockProps} from '@github-ui/relay-test-utils/RelayTestFactories'
import {graphql} from 'relay-runtime'
import type {ListAuthorFilterCurrentViewerTestQuery} from './__generated__/ListAuthorFilterCurrentViewerTestQuery.graphql'
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

test('renders a menu with authors', async () => {
  const {user} = renderListAuthorFilter(() => {}, {})
  const button = screen.getByTestId('authors-anchor-button')

  expect(button).toBeInTheDocument()
  expect(button.textContent).toBe('Author')
  expect(screen.queryByPlaceholderText('Filter authors')).not.toBeInTheDocument()

  await user.click(button)
  const list = screen.queryByPlaceholderText('Filter authors')

  expect(list).toBeInTheDocument()
  expect(list).toBeVisible()

  const listItems = screen.getAllByRole('option')

  expect(listItems.length).toBe(4)
  expect(listItems[0]).toHaveTextContent('monalisaoctocat')
  expect(listItems[1]).toHaveTextContent('loginAnameA')
  expect(listItems[2]).toHaveTextContent('loginBnameB')
  expect(listItems[3]).toHaveTextContent('loginCnameC')
})

test('when selection is changed, it calls the provided callback', async () => {
  const callback = jest.fn()
  const {user} = renderListAuthorFilter(callback, {})

  expect(callback).not.toHaveBeenCalled()

  const button = screen.getByTestId('authors-anchor-button')

  expect(button).toBeInTheDocument()

  await user.click(button)
  const list = screen.queryByLabelText('User results')

  expect(list).toBeInTheDocument()
  expect(list).toBeVisible()

  const listItems = screen.getAllByRole('option')

  expect(listItems[0]).toHaveTextContent('monalisaoctocat')

  await user.click(listItems[1]!)

  expect(list).not.toBeVisible()
  expect(callback).toHaveBeenCalledWith(
    'dirty query not submitted yet author:loginA',
    '/issues/repo?q=dirty%20query%20not%20submitted%20yet%20author%3AloginA',
  )
})

test('correctly shows selected author and updates query on new selection', async () => {
  mockUseQueryEditContext.mockReturnValue({
    debouncedDirtySearchQuery: 'dirty query author:loginB',
  })

  const callback = jest.fn()
  const {user} = renderListAuthorFilter(callback, {selectedAuthor: 'loginB'})
  const button = screen.getByTestId('authors-anchor-button')

  expect(button).toBeInTheDocument()

  await user.click(button)
  const list = screen.queryByLabelText('User results')

  expect(list).toBeInTheDocument()
  expect(list).toBeVisible()
  expect(screen.getByRole('option', {selected: true})).toHaveTextContent('loginBnameB')

  const listItems = screen.getAllByRole('option')

  expect(listItems[1]).toHaveTextContent('monalisaoctocat')
  await user.click(listItems[1]!)

  expect(list).not.toBeVisible()
  expect(callback).toHaveBeenCalledWith(
    'dirty query author:monalisa',
    '/issues/repo?q=dirty%20query%20author%3Amonalisa',
  )
})

// For `ui/packages/item-picker/hooks/useViewer.tsx`
const _ = graphql`
  query ListAuthorFilterCurrentViewerTestQuery {
    safeViewer {
      ...AssigneePickerAssignee
    }
  }
`

const renderListAuthorFilter = (
  onSelectCallback: () => void,
  {selectedAuthor = undefined, query = null}: {selectedAuthor?: string; query?: string | null},
) => {
  type Queries = {
    fetchQuery: AssigneePickerSearchAssignableRepositoryUsersQuery
    currentViewerQuery: ListAuthorFilterCurrentViewerTestQuery
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
          loginNames: selectedAuthor,
          first: selectedAuthor ? 1 : 30,
          capabilities: [],
        },
      },
      currentViewerQuery: {
        type: 'lazy',
      },
    },
  }

  const authors = [
    buildAssignee({login: 'loginA', name: 'nameA'}),
    buildAssignee({login: 'loginB', name: 'nameB'}),
    buildAssignee({login: 'loginC', name: 'nameC'}),
  ].filter(author => selectedAuthor === undefined || author.login === selectedAuthor)

  return renderRelay<Queries>(
    () => (
      <ListAuthorFilter nested={false} repo={{name: 'issues', owner: 'github'}} applySectionFilter={onSelectCallback} />
    ),
    {
      relay: {
        ...mockQueries,
        mockResolvers: {
          Repository() {
            return {
              suggestedActors: {
                nodes: authors,
                totalCount: authors.length,
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
