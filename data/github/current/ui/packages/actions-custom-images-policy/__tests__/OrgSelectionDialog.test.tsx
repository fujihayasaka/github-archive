import {act, screen} from '@testing-library/react'
import {render, setupUserEvent} from '@github-ui/react-core/test-utils'
// eslint-disable-next-line no-restricted-imports
import {mockFetch} from '@github-ui/mock-fetch'
import {OrgSelectionDialog} from '../OrgSelectionDialog'
import {getOrgSelectionDialogProps} from '../test-utils/mock-data'

test('Renders the OrgSelectionDialog', () => {
  const props = getOrgSelectionDialogProps()
  render(<OrgSelectionDialog {...props} />)

  /* Not many good places to hang a data-testid on the dialog, so rely on the list view */
  expect(screen.getByTestId('select-orgs-list')).toBeInTheDocument()
})

test('Apply button is disabled and Cancel is enabled by default', () => {
  const props = getOrgSelectionDialogProps()
  render(<OrgSelectionDialog {...props} />)

  expect(screen.getByRole('button', {name: /cancel/i})).toBeEnabled()
  expect(screen.getByRole('button', {name: /apply/i})).toBeDisabled()
})

test('Cancel button does not submit any changes to the action', () => {
  const props = getOrgSelectionDialogProps()
  mockWindowLocationReload()
  mockFetch.mockRouteOnce(props.action)

  render(<OrgSelectionDialog {...props} />)

  expect(mockFetch.fetch).not.toHaveBeenCalled()
  expect(window.location.reload).not.toHaveBeenCalled()
})

test('Apply button is enabled when changes are present', async () => {
  const props = getOrgSelectionDialogProps()

  render(<OrgSelectionDialog {...props} />)
  expect(screen.getByRole('button', {name: /apply/i})).toBeDisabled()

  const firstCheckbox = screen.getByRole('checkbox', {name: `Select: ${props.organizations[0]!.name}`})
  await act(async () => await firstCheckbox.click())

  expect(screen.getByRole('button', {name: /apply/i})).toBeEnabled()
})

for (const isSelected of [true, false]) {
  test(`Clicking the apply button submits changes and reloads the page: selected: ${isSelected}`, async () => {
    const props = {...getOrgSelectionDialogProps(), organizations: [{id: 1, name: 'org1', selected: isSelected}]}
    mockWindowLocationReload()
    mockFetch.mockRouteOnce(props.action)

    render(<OrgSelectionDialog {...props} />)

    const firstCheckbox = screen.getByRole('checkbox', {name: `Select: ${props.organizations[0]!.name}`})
    await act(async () => await firstCheckbox.click())

    const applyButton = screen.getByRole('button', {name: /apply/i})
    await act(async () => await applyButton.click())

    // Clicking the checkbox flips the selection
    const shouldBeSelected = !isSelected
    const changedIds = [props.organizations[0]!.id]
    expect(mockFetch.fetch).toHaveBeenCalledWith(
      props.action,
      expect.objectContaining({
        method: 'PUT',
        body: JSON.stringify({
          enabledOrgIds: shouldBeSelected ? changedIds : [],
          disabledOrgIds: shouldBeSelected ? [] : changedIds,
        }),
      }),
    )
    expect(window.location.reload).toHaveBeenCalled()
  })
}

test('Filtering the list updates the view', async () => {
  jest.useFakeTimers()

  const props = getOrgSelectionDialogProps()
  render(<OrgSelectionDialog {...props} />)

  const filterInput = screen.getByTestId('org-filter-textinput')
  const userEvent = setupUserEvent()
  await userEvent.type(filterInput, 'org1')

  // Wait for the debounce
  await act(jest.runAllTimers)

  expect(screen.getByRole('checkbox', {name: /org1/i})).toBeInTheDocument()
  expect(screen.queryByRole('checkbox', {name: /org2/i})).not.toBeInTheDocument()
  expect(screen.queryByRole('checkbox', {name: /org3/i})).not.toBeInTheDocument()
})

function mockWindowLocationReload() {
  Object.defineProperty(window, 'location', {
    writable: true,
    value: {
      reload: jest.fn(),
    },
  })
}
