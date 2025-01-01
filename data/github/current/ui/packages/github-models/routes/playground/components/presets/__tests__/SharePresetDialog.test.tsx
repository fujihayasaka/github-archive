import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {SharePresetDialog, type SharePresetDialogProps} from '../SharePresetDialog'

const onClose = jest.fn()
const defaultProps = {
  onClose,
  playgroundUrl: 'https://example.com',
  urlIdentifier: 'monalisa/preset-a',
} satisfies SharePresetDialogProps

const shareableText = 'Anyone with the URL will be able to view and use this prompt, but not edit.'

describe('SharePresetDialog', () => {
  afterEach(() => {
    jest.resetAllMocks()
  })

  test('loads SharePresetDialog with shareable URL', async () => {
    const shareableUrl = `${defaultProps.playgroundUrl}/?preset=${defaultProps.urlIdentifier}`

    const {user} = render(<SharePresetDialog {...defaultProps} />)

    expect(screen.getByTestId('share-preset-dialog')).toBeInTheDocument()
    expect(screen.getByRole('dialog', {name: 'Share prompt'})).toBeInTheDocument()

    expect(screen.getByText(shareableText)).toBeInTheDocument()
    expect(screen.getByLabelText(shareableUrl)).toBeInTheDocument()

    // There are multiple Copy url to clipboard elements
    expect(screen.getAllByRole('button', {name: 'Copy url to clipboard'}).length).toBeGreaterThan(0)
    expect(onClose).not.toHaveBeenCalled()
    const closeButton = screen.getByRole('button', {name: 'Close'})
    expect(closeButton).toBeInTheDocument()

    await user.click(closeButton)

    expect(onClose).toHaveBeenCalledTimes(1)
  })
})
