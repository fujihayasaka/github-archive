import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {RelayEnvironmentProvider, type OperationDescriptor} from 'react-relay'
import {MockPayloadGenerator, createMockEnvironment} from 'relay-test-utils'

import {ListIssueTypeFilter} from '../ListIssueTypeFilter'
import {IssueTypePickerGraphqlQuery} from '@github-ui/item-picker/IssueTypePicker'
import {buildIssueType} from '@github-ui/item-picker/test-utils/IssueTypePickerHelpers'
import {SPECIAL_VALUES} from '@github-ui/item-picker/Placeholders'
import type {FilterBarPickerProps} from '../ListItemsHeaderWithoutBulkActions'
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
  mockUseQueryEditContext.mockReturnValue({debouncedDirtySearchQuery: 'dirty query not submitted yet type:bug'})
})

test('renders a menu with issue types', async () => {
  const {user} = renderListIssueTypeFilter(() => {})

  const button = screen.getByRole('button', {name: 'Filter by issue type'})
  expect(button).toBeInTheDocument()

  expect(screen.queryByRole('listbox', {name: 'Issue Type results'})).not.toBeInTheDocument()

  await user.click(button)

  const list = screen.getByRole('listbox', {name: 'Issue Type results'})
  expect(list).toBeInTheDocument()

  const listItems = screen.getAllByRole('option')

  expect(listItems.length).toBe(3)
  expect(listItems[0]).toHaveTextContent(SPECIAL_VALUES.noTypeData.name)
  expect(listItems[1]).toHaveTextContent('bug')
  expect(listItems[2]).toHaveTextContent('enhancement')
})

test('when selection is changed, it calls the provided callback', async () => {
  const callback = jest.fn()

  const {user} = renderListIssueTypeFilter(callback)
  expect(callback).not.toHaveBeenCalled()

  const button = screen.getByRole('button', {name: 'Filter by issue type'})
  await user.click(button)
  const list = screen.getByRole('listbox', {name: 'Issue Type results'})

  expect(list).toBeInTheDocument()
  expect(list).toBeVisible()

  const listItems = screen.getAllByRole('option')

  expect(listItems[2]).toHaveTextContent('enhancement')

  await user.click(listItems[2]!)

  expect(list).not.toBeVisible()
  expect(callback).toHaveBeenCalledWith(
    'dirty query not submitted yet type:enhancement',
    '/issues/repo?q=dirty%20query%20not%20submitted%20yet%20type%3Aenhancement',
  )
})

test('correctly shows selected issue type and updates query on new selection', async () => {
  const callback = jest.fn()
  const {user} = renderListIssueTypeFilter(callback)
  const button = screen.getByRole('button', {name: 'Filter by issue type'})

  expect(button).toBeInTheDocument()

  await user.click(button)
  const list = screen.getByRole('listbox', {name: 'Issue Type results'})

  expect(list).toBeInTheDocument()
  expect(list).toBeVisible()
  expect(screen.getByRole('option', {selected: true})).toHaveTextContent('bug')

  const listItems = screen.getAllByRole('option')

  expect(listItems[2]).toHaveTextContent('enhancement')
  await user.click(listItems[2]!)

  expect(list).not.toBeVisible()
  expect(callback).toHaveBeenCalledWith(
    'dirty query not submitted yet type:enhancement',
    '/issues/repo?q=dirty%20query%20not%20submitted%20yet%20type%3Aenhancement',
  )
})

const renderListIssueTypeFilter = (onSelectCallback: () => void, overrides: Partial<FilterBarPickerProps> = {}) => {
  const environment = createMockEnvironment()
  environment.mock.queuePendingOperation(IssueTypePickerGraphqlQuery, {owner: 'github', repo: 'issues'})
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {
          issueTypes: {
            edges: [
              {node: buildIssueType({name: 'bug', color: 'RED', description: ''})},
              {node: buildIssueType({name: 'enhancement', color: 'GREEN', description: ''})},
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
        repo={{name: 'issues', owner: 'github'}}
        applySectionFilter={onSelectCallback}
        {...overrides}
      />
    </RelayEnvironmentProvider>,
  )
}
