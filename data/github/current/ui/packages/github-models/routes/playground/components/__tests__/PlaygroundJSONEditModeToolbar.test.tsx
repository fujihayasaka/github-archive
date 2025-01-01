import {within} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {PlaygroundJSONEditModeToolbar} from '../PlaygroundJSONEditModeToolbar'

describe('PlaygroundJSONEditModeToolbar', () => {
  const applyInput = jest.fn().mockName('applyInput')
  const resetInput = jest.fn().mockName('resetInput')

  afterEach(() => {
    jest.resetAllMocks()
  })

  test('renders when JSON is valid', async () => {
    const content = 'hello world'
    const initialContent = 'other content'

    const {container, user} = render(
      <PlaygroundJSONEditModeToolbar
        applyInput={applyInput}
        content={content}
        initialContent={initialContent}
        isValidJSON
        resetInput={resetInput}
      />,
    )

    const cancelButton = within(container).getByRole('button', {name: 'Cancel'})
    expect(cancelButton).toBeInTheDocument()
    const applyChangesButton = within(container).getByRole('button', {name: 'Apply changes'})
    expect(applyChangesButton).toBeInTheDocument()
    expect(within(container).queryByText('Invalid JSON or value')).not.toBeInTheDocument()
    expect(resetInput).not.toHaveBeenCalled()

    await user.click(cancelButton)

    expect(resetInput).toHaveBeenCalledTimes(1)
    expect(applyInput).not.toHaveBeenCalled()

    await user.click(applyChangesButton)

    expect(applyInput).toHaveBeenCalledTimes(1)
    expect(applyInput).toHaveBeenCalledWith(content)
  })

  test('renders when JSON is invalid', () => {
    const content = 'hello world'

    const {container} = render(
      <PlaygroundJSONEditModeToolbar
        applyInput={applyInput}
        content={content}
        initialContent={content}
        isValidJSON={false}
        resetInput={resetInput}
      />,
    )

    expect(within(container).getByText('Invalid JSON or value')).toBeInTheDocument()
    expect(within(container).getByRole('button', {name: 'Apply changes'})).toBeDisabled()
    expect(within(container).getByRole('button', {name: 'Cancel'})).toBeEnabled()
  })

  test('disables Apply Changes button when content has not changed from initial content', () => {
    const content = 'hello world'

    const {container} = render(
      <PlaygroundJSONEditModeToolbar
        applyInput={applyInput}
        content={content}
        initialContent={content}
        isValidJSON
        resetInput={resetInput}
      />,
    )

    expect(within(container).getByRole('button', {name: 'Apply changes'})).toBeDisabled()
    expect(within(container).getByRole('button', {name: 'Cancel'})).toBeEnabled()
    expect(within(container).queryByText('Invalid JSON or value')).not.toBeInTheDocument()
  })
})
