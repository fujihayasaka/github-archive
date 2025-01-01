import {render} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {RelayEnvironmentProvider, type OperationDescriptor} from 'react-relay'
import {MockPayloadGenerator, createMockEnvironment} from 'relay-test-utils'

import {ListIssueTypeFilter} from '../ListIssueTypeFilter'
import {IssueTypePickerGraphqlQuery} from '@github-ui/item-picker/IssueTypePicker'
import {mockRelayId} from '@github-ui/relay-test-utils/RelayComponents'
import {TEST_IDS} from '../../../../constants/test-ids'

const mockUseQueryContext = jest.fn()
jest.mock('../../../../contexts/QueryContext', () => ({
  useQueryContext: () => mockUseQueryContext({}),
}))

test('renders a menu with issue types', async () => {
  mockUseQueryContext.mockReturnValue({activeSearchQuery: 'aa', currentViewId: 'repo'})
  const {user} = renderListIssueTypeFilter(() => {})

  const button = screen.getByTestId(TEST_IDS.issueTypeAnchorFilter)
  expect(button).toBeInTheDocument()
  expect(button.textContent).toBe('Types')

  expect(screen.queryByPlaceholderText('Filter by issue type')).not.toBeInTheDocument()

  await user.click(button)

  const header = screen.getByText('Filter by issue type')
  expect(header).toBeInTheDocument()

  const listItems = screen.getAllByRole('option')
  expect(listItems.length).toBe(4)
  expect(listItems[0]).toHaveTextContent('No type')
  expect(listItems[1]).toHaveTextContent('Bug')
  expect(listItems[2]).toHaveTextContent('Enhancement')
  expect(listItems[3]).toHaveTextContent('Task')
})

test('when selection is changed, it calls the provided callback', async () => {
  mockUseQueryContext.mockReturnValue({activeSearchQuery: 'aa', currentViewId: 'repo'})
  const callback = jest.fn()

  const {user} = renderListIssueTypeFilter(callback)
  expect(callback).not.toHaveBeenCalled()

  const button = screen.getByTestId(TEST_IDS.issueTypeAnchorFilter)
  expect(button).toBeInTheDocument()
  await user.click(button)

  const searchInput = screen.queryByLabelText('Filter types')
  expect(searchInput).toBeInTheDocument()
  expect(searchInput).toBeVisible()

  const listItems = screen.getAllByRole('option')
  expect(listItems.length).toBe(4)
  expect(listItems[2]).toHaveTextContent('Enhancement')

  await user.click(await within(listItems[2]!).findByText('Enhancement'))

  // Close the picker
  expect(screen.queryByPlaceholderText('Filter types')).not.toBeInTheDocument()
  expect(callback).toHaveBeenCalledWith('aa type:Enhancement', '/issues/repo?q=aa%20type%3AEnhancement')
})

test('can clear selection', async () => {
  mockUseQueryContext.mockReturnValue({activeSearchQuery: 'type:Enhancement', currentViewId: 'repo'})
  const callback = jest.fn()

  const {user} = renderListIssueTypeFilter(callback)
  expect(callback).not.toHaveBeenCalled()

  const button = screen.getByTestId(TEST_IDS.issueTypeAnchorFilter)
  expect(button).toBeInTheDocument()
  await user.click(button)

  const searchInput = screen.queryByLabelText('Filter types')
  expect(searchInput).toBeInTheDocument()
  expect(searchInput).toBeVisible()

  const listItems = screen.getAllByRole('option')
  expect(listItems.length).toBe(4)

  await user.click(await within(listItems[2]!).findByText('Enhancement'))

  // Close the picker
  expect(screen.queryByPlaceholderText('Filter types')).not.toBeInTheDocument()
  expect(callback).toHaveBeenCalledWith('', '/issues/repo')
})

test('replaces selection', async () => {
  mockUseQueryContext.mockReturnValue({activeSearchQuery: 'type:Task type:Enhancement', currentViewId: 'repo'})
  const callback = jest.fn()

  const {user} = renderListIssueTypeFilter(callback)
  expect(callback).not.toHaveBeenCalled()

  const button = screen.getByTestId(TEST_IDS.issueTypeAnchorFilter)
  expect(button).toBeInTheDocument()
  await user.click(button)

  const searchInput = screen.queryByLabelText('Filter types')
  expect(searchInput).toBeInTheDocument()
  expect(searchInput).toBeVisible()

  const listItems = screen.getAllByRole('option')
  expect(listItems.length).toBe(4)

  await user.click(await within(listItems[1]!).findByText('Bug'))

  // Close the picker
  expect(screen.queryByPlaceholderText('Filter types')).not.toBeInTheDocument()
  expect(callback).toHaveBeenCalledWith('type:Bug', '/issues/repo?q=type%3ABug')
})

test('selecting no:type updates the query correctly', async () => {
  mockUseQueryContext.mockReturnValue({activeSearchQuery: 'aa', currentViewId: 'repo'})
  const callback = jest.fn()

  const {user} = renderListIssueTypeFilter(callback)
  expect(callback).not.toHaveBeenCalled()

  const button = screen.getByTestId(TEST_IDS.issueTypeAnchorFilter)
  expect(button).toBeInTheDocument()
  await user.click(button)

  const searchInput = screen.queryByLabelText('Filter types')
  expect(searchInput).toBeInTheDocument()
  expect(searchInput).toBeVisible()

  const listItems = screen.getAllByRole('option')
  expect(listItems.length).toBe(4)

  await user.click(await within(listItems[0]!).findByText('No type'))

  // Close the picker
  expect(screen.queryByPlaceholderText('Filter types')).not.toBeInTheDocument()
  expect(callback).toHaveBeenCalledWith('aa no:type', '/issues/repo?q=aa%20no%3Atype')
})

test('can clear no:type selection', async () => {
  mockUseQueryContext.mockReturnValue({activeSearchQuery: 'no:type', currentViewId: 'repo'})
  const callback = jest.fn()

  const {user} = renderListIssueTypeFilter(callback)
  expect(callback).not.toHaveBeenCalled()

  const button = screen.getByTestId(TEST_IDS.issueTypeAnchorFilter)
  expect(button).toBeInTheDocument()
  await user.click(button)

  const searchInput = screen.queryByLabelText('Filter types')
  expect(searchInput).toBeInTheDocument()
  expect(searchInput).toBeVisible()

  const listItems = screen.getAllByRole('option')
  expect(listItems.length).toBe(4)

  await user.click(await within(listItems[0]!).findByText('No type'))

  // Close the picker
  expect(screen.queryByPlaceholderText('Filter types')).not.toBeInTheDocument()
  expect(callback).toHaveBeenCalledWith('', '/issues/repo')
})

const renderListIssueTypeFilter = (onSelectCallback: () => void) => {
  const environment = createMockEnvironment()
  environment.mock.queuePendingOperation(IssueTypePickerGraphqlQuery, {owner: 'github', repo: 'issues'})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {
          issueTypes: {
            edges: [
              {
                node: {
                  id: mockRelayId(),
                  name: 'Bug',
                },
              },
              {
                node: {
                  id: mockRelayId(),
                  name: 'Enhancement',
                },
              },
              {
                node: {
                  id: mockRelayId(),
                  name: 'Task',
                },
              },
            ],
          },
        }
      },
    })
  })

  return render(
    <RelayEnvironmentProvider environment={environment}>
      <ListIssueTypeFilter
        nested={false}
        repo={{name: 'github', owner: 'issues'}}
        applySectionFilter={onSelectCallback}
      />
    </RelayEnvironmentProvider>,
  )
}
