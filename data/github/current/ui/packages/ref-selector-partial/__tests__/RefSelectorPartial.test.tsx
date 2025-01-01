import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {RefSelectorPartial} from '../RefSelectorPartial'
import {getRefSelectorPartialProps} from '../test-utils/mock-data'
import {SearchIndex} from '@github-ui/ref-selector/search-index'

jest.spyOn(window, 'requestAnimationFrame').mockImplementation((cb: FrameRequestCallback) => {
  cb(0)
  return 0
})

test('Renders the RefSelectorPartial', () => {
  const props = getRefSelectorPartialProps()
  render(<RefSelectorPartial {...props} />)
  expect(screen.getByText(props.defaultBranch ?? '')).toBeInTheDocument()
})

test('Renders the hidden form input when form data is provided', () => {
  const props = {
    ...getRefSelectorPartialProps(),
    formData: {
      id: 'hidden-input-id',
      name: 'ref-name',
      autosubmit: true,
    },
  }

  // Render the component
  render(<RefSelectorPartial {...props} />)
  expect(screen.getByDisplayValue(props.defaultBranch ?? '')).toBeInTheDocument()

  // Get the hidden input
  const input = screen.getByTestId('ref-selector-partial-hidden-input')
  expect(input).toBeInTheDocument()
  expect(input).toHaveAttribute('name', props.formData?.name)
  expect(input).toHaveAttribute('value', props.defaultBranch)
  expect(input).toHaveAttribute('id', props.formData?.id)
})

test('Does not render the hidden form input when form data is not provided', () => {
  const props = getRefSelectorPartialProps()
  render(<RefSelectorPartial {...props} />)
  expect(screen.queryByTestId('ref-selector-partial-hidden-input')).not.toBeInTheDocument()
})

test('Dispatches event on contianer if "dispatchEvent" is true', async () => {
  const props = getRefSelectorPartialProps()

  const mockedResults = ['main', 'current-branch', 'another-branch']
  jest.spyOn(SearchIndex.prototype, 'fetchData').mockImplementation(async function (this: SearchIndex) {
    this.knownItems = mockedResults
    this.isLoading = false
    this.render()
  })

  const {user} = render(<RefSelectorPartial {...props} dispatchEvent />)

  const container = screen.getByTestId('ref-selector-partial-container')

  const dispatchEventSpy = jest.spyOn(container, 'dispatchEvent')

  // Opens the ref selector
  const button = screen.getByRole('button')
  await user.click(button)

  await user.click(screen.getByText('another-branch'))

  expect(dispatchEventSpy).toHaveBeenCalled()
  const changeEventCall = dispatchEventSpy.mock.calls.find(([event]) => event.type === 'ref-selector-partial:change')

  const changeEvent = changeEventCall?.[0] as CustomEvent
  expect(changeEvent).toBeDefined()
  expect(changeEvent.detail.refName).toBe('another-branch')
})
