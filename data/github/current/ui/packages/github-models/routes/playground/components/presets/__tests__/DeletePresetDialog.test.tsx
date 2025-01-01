import {screen} from '@testing-library/react'
import {render} from '@github-ui/react-core/test-utils'
import {DeletePresetDialog} from '../DeletePresetDialog'
import {mockPreset} from '../../../__tests__/mocks'

const mockDeletePreset = jest.fn().mockName('deletePreset')
jest.mock('../../../../../utils/presets', () => ({
  deletePreset: (...args: unknown[]) => mockDeletePreset(...args),
}))

describe('DeletePresetDialog', () => {
  const onClose = jest.fn()
  const onSuccess = jest.fn()

  afterEach(() => {
    jest.clearAllMocks()
  })

  test('calls deletePreset without errors', async () => {
    const {user} = render(<DeletePresetDialog onClose={onClose} onSuccess={onSuccess} selectedPreset={mockPreset} />)

    expect(screen.getByTestId('delete-preset-dialog')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Close'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('alertdialog', {name: 'Delete prompt'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1, name: 'Delete prompt'})).toBeInTheDocument()
    expect(screen.queryByRole('heading', {level: 2, name: 'Something went wrong'})).not.toBeInTheDocument()

    const deleteButton = screen.getByRole('button', {name: 'Delete'})
    expect(deleteButton).toBeInTheDocument()
    mockDeletePreset.mockResolvedValue({ok: true, json: () => Promise.resolve({})})
    await user.click(deleteButton)

    expect(mockDeletePreset).toHaveBeenCalledWith({urlIdentifier: mockPreset.urlIdentifier})
    expect(onSuccess).toHaveBeenCalledTimes(1)
    expect(onClose).toHaveBeenCalledTimes(1)
  })

  test('renders when deletePreset fails with errors', async () => {
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

    const {user} = render(<DeletePresetDialog onClose={onClose} onSuccess={onSuccess} selectedPreset={mockPreset} />)
    mockDeletePreset.mockRejectedValue(new Error('Something really bad happened'))

    expect(screen.getByTestId('delete-preset-dialog')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Delete'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('alertdialog', {name: 'Delete prompt'})).toBeInTheDocument()
    expect(screen.getByRole('heading', {level: 1, name: 'Delete prompt'})).toBeInTheDocument()
    expect(screen.queryByRole('heading', {level: 2, name: 'Something went wrong'})).not.toBeInTheDocument()

    const deleteButton = screen.getByRole('button', {name: 'Delete'})
    expect(deleteButton).toBeInTheDocument()
    await user.click(deleteButton)

    expect(mockDeletePreset).toHaveBeenCalledWith({urlIdentifier: mockPreset.urlIdentifier})
    expect(onSuccess).not.toHaveBeenCalled()
    expect(onClose).not.toHaveBeenCalled()

    expect(screen.getByRole('heading', {level: 2, name: 'Something went wrong'})).toBeInTheDocument()
    expect(screen.getByText(`Failed to delete ${mockPreset.name} preset. Try again later.`)).toBeInTheDocument()

    const closeButton = screen.getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()
    await user.click(closeButton)

    expect(onClose).toHaveBeenCalledTimes(1)
    expect(onSuccess).not.toHaveBeenCalled()
  })
})
