import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {DeletePresetDialog} from '../DeletePresetDialog'
import {mockPreset} from '../../../__tests__/mocks'

describe('DeletePresetDialog', () => {
  const onClose = jest.fn()
  const onSubmit = jest.fn()

  afterEach(() => {
    jest.clearAllMocks()
  })

  test('renders without errors', async () => {
    const {user} = render(<DeletePresetDialog onClose={onClose} onSubmit={onSubmit} selectedPreset={mockPreset} />)

    expect(screen.getByTestId('delete-preset-dialog')).toBeInTheDocument()
    const deleteButton = screen.getByRole('button', {name: 'Delete'})
    expect(deleteButton).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('alertdialog', {name: 'Delete preset'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1, name: 'Delete preset'})).toBeInTheDocument()
    expect(screen.queryByRole('heading', {level: 2, name: 'Something went wrong'})).not.toBeInTheDocument()
    expect(onSubmit).not.toHaveBeenCalled()

    await user.click(deleteButton)

    expect(onSubmit).toHaveBeenCalledTimes(1)
    expect(onSubmit).toHaveBeenCalledWith(mockPreset)
    expect(onClose).not.toHaveBeenCalled()
  })

  test('renders with errors', async () => {
    // Note: this error occurs because of the Banner component that is added to the UI due to the `errors` prop. The
    // CSS parser for jsdom does not support some of the styling syntax for Banner and will fail with an error
    // containing the message below. Tracking issue: https://github.com/github/primer/issues/3882
    // eslint-disable-next-line no-console
    const originalConsoleError = console.error
    jest.spyOn(console, 'error').mockImplementation((value, ...args) => {
      if (!value?.message?.includes('Could not parse CSS stylesheet')) {
        originalConsoleError(value, ...args)
      }
    })
    const errors = 'o noes'

    const {user} = render(
      <DeletePresetDialog errors={errors} onClose={onClose} onSubmit={onSubmit} selectedPreset={mockPreset} />,
    )

    expect(screen.getByTestId('delete-preset-dialog')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Delete'})).toBeInTheDocument()
    const closeButton = screen.getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('alertdialog', {name: 'Delete preset'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1, name: 'Delete preset'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 2, name: 'Something went wrong'})).toBeInTheDocument()
    expect(screen.getByText(errors)).toBeInTheDocument()
    expect(onClose).not.toHaveBeenCalled()

    await user.click(closeButton)

    expect(onClose).toHaveBeenCalledTimes(1)
    expect(onSubmit).not.toHaveBeenCalled()
  })
})
