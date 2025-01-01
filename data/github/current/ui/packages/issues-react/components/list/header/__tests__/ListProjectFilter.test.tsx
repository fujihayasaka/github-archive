import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor, within} from '@testing-library/react'
import {RelayEnvironmentProvider, type OperationDescriptor} from 'react-relay'
import {MockPayloadGenerator} from 'relay-test-utils'

import {ListProjectFilter} from '../ListProjectFilter'
import {ProjectPickerGraphqlQuery} from '@github-ui/item-picker/ProjectPicker'
import {buildProject} from '@github-ui/item-picker/test-utils/ProjectPickerHelpers'
import {createRelayMockEnvironment} from '@github-ui/relay-test-utils/RelayMockEnvironment'
import type {FilterBarPickerProps} from '../ListItemsHeaderWithoutBulkActions'

const mockUseQueryContext = jest.fn().mockReturnValue({activeSearchQuery: 'aa', currentViewId: 'repo'})
const mockUseQueryEditContext = jest.fn().mockReturnValue({debouncedDirtySearchQuery: null})

jest.mock('../../../../contexts/QueryContext', () => ({
  useQueryContext: () => mockUseQueryContext({}),
  useQueryEditContext: () => mockUseQueryEditContext({}),
}))

test('renders a menu with projects', async () => {
  // this test is emitting the following warning that we're not able to track down
  // Warning: Each child in a list should have a unique "key" prop
  jest.spyOn(console, 'error').mockImplementation()

  const {user} = renderListProjectFilter(() => {})

  const button = screen.getByTestId('projects-anchor-button')
  expect(button).toBeInTheDocument()
  expect(button.textContent).toBe('Projects')

  expect(screen.queryByPlaceholderText('Filter projects')).not.toBeInTheDocument()

  await user.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(2)
  })

  const list = screen.queryByPlaceholderText('Filter projects')
  expect(list).toBeInTheDocument()

  const listItems = screen.getAllByRole('option')
  expect(listItems.length).toBe(2)
  expect(listItems[0]).toHaveTextContent('Project 1')
  expect(listItems[1]).toHaveTextContent('Project 2')
})

test('renders no projects as disabled', async () => {
  const {user} = renderListProjectFilter(() => {})

  const button = screen.getByTestId('projects-anchor-button')
  expect(button).toBeInTheDocument()
  expect(button.textContent).toBe('Projects')

  expect(screen.queryByPlaceholderText('Filter projects')).not.toBeInTheDocument()

  await user.click(button)

  await waitFor(() => {
    expect(screen.getAllByRole('option')).toHaveLength(2)
  })

  const listItems = screen.getAllByRole('option')
  expect(listItems.length).toBe(2)

  for (const listItem of listItems) {
    const childElements = within(listItem).queryAllByRole('generic', {hidden: true})
    expect(childElements[1]).not.toHaveAttribute('disabled')
  }
})

test('when selection is changed, it calls the provided callback', async () => {
  const callback = jest.fn()

  const {user} = renderListProjectFilter(callback)
  expect(callback).not.toHaveBeenCalled()

  const button = screen.getByTestId('projects-anchor-button')
  expect(button).toBeInTheDocument()
  await user.click(button)

  const list = screen.queryByLabelText('Project results')
  expect(list).toBeInTheDocument()

  expect(list).toBeVisible()

  const listItems = within(list!).getAllByRole('option')
  expect(listItems.length).toBe(2)

  expect(listItems[0]).toHaveTextContent('Project 1')

  await user.click(await within(listItems[0]!).findByText('Project 1'))
  expect(within(list!).getAllByRole('option')[0]!).toHaveAttribute('aria-selected', 'true')

  // Close the picker
  await user.keyboard('{Escape}')

  expect(screen.queryByPlaceholderText('Filter projects')).not.toBeInTheDocument()

  expect(callback).toHaveBeenCalled()
})

test('when selection has not changed, it does not call the provided callback', async () => {
  const callback = jest.fn()

  const {user} = renderListProjectFilter(callback)
  expect(callback).not.toHaveBeenCalled()

  const button = screen.getByTestId('projects-anchor-button')
  expect(button).toBeInTheDocument()
  await user.click(button)

  // Close the picker
  await user.keyboard('{Escape}')

  expect(callback).not.toHaveBeenCalled()
})

describe('when list project filter is render on the overflow menu', () => {
  test('opens list project filter on the overflow menu when pressed enter', async () => {
    const {user} = renderListProjectFilter(() => {}, {nested: true})

    const menuitem = screen.getByRole('menuitem', {name: 'Projects...'})

    expect(menuitem).toBeInTheDocument()
    // focus on the menu item
    menuitem.focus()
    await user.keyboard('{enter}')

    const list = screen.queryByPlaceholderText('Filter projects')
    expect(list).toBeInTheDocument()

    const listItems = screen.getAllByRole('option')
    expect(listItems.length).toBe(2)
    expect(listItems[0]).toHaveTextContent('Project 1')
    expect(listItems[1]).toHaveTextContent('Project 2')
  })
  test('opens list project filter on the overflow menu when pressed space', async () => {
    const {user} = renderListProjectFilter(() => {}, {nested: true})

    const menuitem = screen.getByRole('menuitem', {name: 'Projects...'})

    expect(menuitem).toBeInTheDocument()
    // focus on the menu item
    menuitem.focus()
    await user.keyboard(' ')

    const list = screen.queryByPlaceholderText('Filter projects')
    expect(list).toBeInTheDocument()

    const listItems = screen.getAllByRole('option')
    expect(listItems.length).toBe(2)
    expect(listItems[0]).toHaveTextContent('Project 1')
    expect(listItems[1]).toHaveTextContent('Project 2')
  })
})

const renderListProjectFilter = (onSelectCallback: () => void, overrides: Partial<FilterBarPickerProps> = {}) => {
  const {environment} = createRelayMockEnvironment()

  environment.mock.queuePendingOperation(ProjectPickerGraphqlQuery, {
    owner: 'github',
    repo: 'issues',
  })
  environment.mock.queueOperationResolver((operation: OperationDescriptor) => {
    return MockPayloadGenerator.generate(operation, {
      Repository() {
        return {
          projectsV2: {
            nodes: [
              buildProject({title: 'Project 1', closed: false, viewerCanUpdate: false}),
              buildProject({title: 'Project 2', closed: false, viewerCanUpdate: true}),
            ],
          },
          projects: {nodes: []},
          recentProjects: {edges: []},
          owner: {
            projectsV2: {edges: []},
            recentProjects: {edges: []},
            projects: {nodes: []},
          },
        }
      },
    })
  })

  return render(
    <RelayEnvironmentProvider environment={environment}>
      <ListProjectFilter
        nested={false}
        repo={{name: 'github', owner: 'issues'}}
        applySectionFilter={() => onSelectCallback()}
        {...overrides}
      />
    </RelayEnvironmentProvider>,
  )
}
