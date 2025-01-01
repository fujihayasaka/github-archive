import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import {ActionsCustomImagesPolicy} from '../ActionsCustomImagesPolicy'
import {getActionsCustomImagesPolicyProps} from '../test-utils/mock-data'
import {AccessPolicy} from '../types'

test('Renders the ActionsCustomImagesPolicy', () => {
  const props = getActionsCustomImagesPolicyProps()
  render(<ActionsCustomImagesPolicy {...props} />)

  // The 'none' radio button should be selected by default
  expect(screen.getByRole('radio', {name: /disabled for all organizations/i})).toBeChecked()
})

test('Changing the checked radio button submits the selection', async () => {
  const props = getActionsCustomImagesPolicyProps()

  mockWindowLocationReload()
  mockFetch.mockRouteOnce(props.action)

  render(<ActionsCustomImagesPolicy {...props} />)

  const allRadioButton = screen.getByRole('radio', {name: /Enable for all organizations/i})
  await act(async () => await allRadioButton.click())

  expect(mockFetch.fetch).toHaveBeenCalledWith(
    props.action,
    expect.objectContaining({
      method: 'PUT',
      body: JSON.stringify({
        accessPolicy: 'all',
      }),
    }),
  )

  expect(window.location.reload).toHaveBeenCalled()
})

test('Org selection button is shown when policy is set to "selected"', () => {
  const props = {...getActionsCustomImagesPolicyProps(), accessPolicy: AccessPolicy.Selected}
  render(<ActionsCustomImagesPolicy {...props} />)

  expect(screen.getByTestId('select-orgs-button')).toBeInTheDocument()
})

for (const accessPolicy of [AccessPolicy.All, AccessPolicy.None]) {
  test(`Org selection button is not shown when policy is set to "${accessPolicy}"`, () => {
    const props = {...getActionsCustomImagesPolicyProps(), accessPolicy}
    render(<ActionsCustomImagesPolicy {...props} />)

    expect(screen.queryByTestId('select-orgs-button')).not.toBeInTheDocument()
  })
}

test('Org selection button shows number of selected orgs', () => {
  const props = {...getActionsCustomImagesPolicyProps(), accessPolicy: AccessPolicy.Selected}
  render(<ActionsCustomImagesPolicy {...props} />)

  const expectedCount = props.orgs.filter(org => org.selected).length
  expect(screen.getByTestId('select-orgs-button')).toHaveTextContent(`${expectedCount} selected`)
})

test('Org selection button shows dialog on click', async () => {
  const props = {...getActionsCustomImagesPolicyProps(), accessPolicy: AccessPolicy.Selected}
  render(<ActionsCustomImagesPolicy {...props} />)

  const orgSelectionButton = screen.getByTestId('select-orgs-button')
  await act(async () => await orgSelectionButton.click())

  expect(screen.getByTestId('select-orgs-list')).toBeInTheDocument()
})

function mockWindowLocationReload() {
  Object.defineProperty(window, 'location', {
    writable: true,
    value: {
      reload: jest.fn(),
    },
  })
}
