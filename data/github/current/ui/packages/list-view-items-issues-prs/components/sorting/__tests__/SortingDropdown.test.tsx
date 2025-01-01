import {screen} from '@testing-library/react'
import {render, type User} from '@github-ui/react-core/test-utils'
import {composeStory, type Meta} from '@storybook/react'

import {getSelectedSortOptionKeyFromQuery, SortingDropdown} from '../SortingDropdown'
import {validQueries} from './constants'
import {SortingDropdownExample} from '../SortingDropdown.stories'

const meta = {
  component: SortingDropdown,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  decorators: [Story => <Story />],
} satisfies Meta<typeof SortingDropdown>

const SortingDropdownTestComponent = composeStory(SortingDropdownExample, meta)

test('renders the dropdown with default value when query is empty', async () => {
  const {user} = render(<SortingDropdownTestComponent activeSearchQuery="" />)

  expect(screen.getByRole('button', {name: 'Newest'})).toBeInTheDocument()

  await openSortDropdown(user, 'Newest')

  const createdOn = screen.getByRole('menuitemradio', {name: 'Created on'})
  expectButtonIsCheckedAndEnabled(createdOn)

  // Descending direction is selected and button is not disabled
  const newestButton = screen.getByRole('menuitemradio', {name: 'Newest'})
  expectButtonIsCheckedAndEnabled(newestButton)

  // Ascending direction is not selected and button is not disabled
  const oldestButton = screen.getByRole('menuitemradio', {name: 'Oldest'})
  expectButtonIsNotCheckedAndEnabled(oldestButton)
})

test('does not select default value when sort contains invalid value', async () => {
  const {user} = render(<SortingDropdownTestComponent activeSearchQuery="is:open sort:asdfasdf" />)

  await openSortDropdown(user, 'Sort')

  const options = screen.getAllByRole('menuitemradio')

  for (const option of options) {
    expect(option).not.toBeChecked()
  }
})

test('can select sort option and applies direction correctly', async () => {
  const {user} = render(<SortingDropdownTestComponent activeSearchQuery="sort:comments-desc" />)

  await openSortDropdown(user, 'Comments')

  await user.click(screen.getByRole('menuitemradio', {name: 'Last updated'}))

  expect(screen.getByRole('button', {name: 'Updated'})).toBeInTheDocument()

  await openSortDropdown(user, 'Updated')

  // Descending direction is selected and button is not disabled
  const newestButton = screen.getByLabelText('Newest')
  expectButtonIsCheckedAndEnabled(newestButton)

  // Ascending direction is not selected and button is not disabled
  const oldestButton = screen.getByLabelText('Oldest')
  expectButtonIsNotCheckedAndEnabled(oldestButton)
})

test('can select sort direction and applies current sort option correctly', async () => {
  const {user} = render(<SortingDropdownTestComponent activeSearchQuery="sort:comments-desc" />)

  await openSortDropdown(user, 'Comments')

  // Descending direction is selected and button is not disabled
  const descButton = screen.getByLabelText('Descending')
  expectButtonIsCheckedAndEnabled(descButton)

  // Ascending direction is not selected and button is not disabled
  const ascButton = screen.getByLabelText('Ascending')
  expectButtonIsNotCheckedAndEnabled(ascButton)

  await user.click(ascButton)
  await openSortDropdown(user, 'Comments')

  // Ascending direction is now selected
  expect(screen.getByLabelText('Ascending')).toBeChecked()
  expect(screen.getByLabelText('Descending')).not.toBeChecked()
})

test('disables direction selection when sorting by reaction', async () => {
  const {user} = render(<SortingDropdownTestComponent activeSearchQuery="is:open sort:reactions-+1" />)

  await openSortDropdown(user, 'Thumbs up')

  // Ascending direction is not selected and button disabled
  const ascButton = screen.getByLabelText('Ascending')
  expectButtonIsNotCheckedAndDisabled(ascButton)

  // Descending direction is selected and button disabled
  const descButton = screen.getByLabelText('Descending')
  expectButtonIsCheckedAndDisabled(descButton)
})

test('disables direction selection when sorting by relevance', async () => {
  const {user} = render(<SortingDropdownTestComponent activeSearchQuery="is:open sort:relevance" />)

  await openSortDropdown(user, 'Best match')

  // Ascending direction is not selected and button disabled
  const ascButton = screen.getByLabelText('Ascending')
  expectButtonIsNotCheckedAndDisabled(ascButton)

  // Descending direction is selected and button disabled
  const descButton = screen.getByLabelText('Descending')
  expectButtonIsCheckedAndDisabled(descButton)
})

describe('getSelectedSortOptionKeyFromQuery', () => {
  test.each(Object.entries(validQueries))(`returns the selected label from the query %s`, (query, key) => {
    const selectedKey = getSelectedSortOptionKeyFromQuery(query)

    expect(selectedKey).toEqual(key)
  })

  test('returns `created` if query is empty', () => {
    const selectedKey = getSelectedSortOptionKeyFromQuery('')

    expect(selectedKey).toEqual('created')
  })

  // When an invalid sort option is supplied, results are sorted by relevance
  test('returns `relevance` if query is invalid', () => {
    const selectedKey = getSelectedSortOptionKeyFromQuery('non-existing-query')

    expect(selectedKey).toEqual('relevance')
  })
})

async function openSortDropdown(user: User, selectedLabel: string) {
  await user.click(screen.getByRole('button', {name: selectedLabel}))
}

function expectButtonIsCheckedAndEnabled(button: HTMLElement) {
  expect(button).toBeInTheDocument()
  expect(button).toBeChecked()
  expect(button).not.toHaveAttribute('aria-disabled')
}

function expectButtonIsNotCheckedAndEnabled(button: HTMLElement) {
  expect(button).toBeInTheDocument()
  expect(button).not.toBeChecked()
  expect(button).not.toHaveAttribute('aria-disabled')
}

function expectButtonIsCheckedAndDisabled(button: HTMLElement) {
  expect(button).toBeInTheDocument()
  expect(button).toBeChecked()
  expect(button).toHaveAttribute('aria-disabled', 'true')
}

function expectButtonIsNotCheckedAndDisabled(button: HTMLElement) {
  expect(button).toBeInTheDocument()
  expect(button).not.toBeChecked()
  expect(button).toHaveAttribute('aria-disabled', 'true')
}
