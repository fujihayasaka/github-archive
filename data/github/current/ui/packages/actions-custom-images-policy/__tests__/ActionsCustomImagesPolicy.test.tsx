import {act, screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {mockFetch} from '@github-ui/mock-fetch'
import {ActionsCustomImagesPolicy} from '../ActionsCustomImagesPolicy'
import {getActionsCustomImagesPolicyProps} from '../test-utils/mock-data'

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

function mockWindowLocationReload() {
  Object.defineProperty(window, 'location', {
    writable: true,
    value: {
      reload: jest.fn(),
    },
  })
}
