import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {ImprovePromptDialog} from '../ImprovePromptDialog'
import {sendEvent} from '@github-ui/hydro-analytics'
import {GenerateSystemPromptClicked, GenerateUserPromptClicked} from '../../../../utils/playground-types'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: jest.fn(),
  }
})

describe('ImprovePromptDialog', () => {
  const onClose = jest.fn()
  const setDialogState = jest.fn()
  const setPromptSuggestionText = jest.fn()
  const setCurrentPrompt = jest.fn()

  it('renders ImprovePromptDialog', () => {
    const currentPrompt = 'test'
    render(
      <ImprovePromptDialog
        onClose={onClose}
        setDialogState={setDialogState}
        currentPrompt={currentPrompt}
        setCurrentPrompt={setCurrentPrompt}
        promptSuggestionText={''}
        setPromptSuggestionText={setPromptSuggestionText}
        type="system"
      />,
    )

    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()
    expect(screen.getByRole('textbox', {name: 'Current prompt'})).toHaveValue(currentPrompt)
    expect(screen.getByRole('textbox', {name: 'What would you like to improve? (optional)'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Improve prompt'})).toBeInTheDocument()
  })

  it('can close ImprovePromptDialog', async () => {
    const currentPrompt = 'test'
    const {user} = render(
      <ImprovePromptDialog
        onClose={onClose}
        setDialogState={setDialogState}
        currentPrompt={currentPrompt}
        setCurrentPrompt={setCurrentPrompt}
        promptSuggestionText={''}
        setPromptSuggestionText={setPromptSuggestionText}
        type="system"
      />,
    )

    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()

    const cancel = screen.getByRole('button', {name: 'Cancel'})
    await user.click(cancel)

    expect(onClose).toHaveBeenCalled()
  })

  it('displays disabled button when currentPrompt is empty', () => {
    render(
      <ImprovePromptDialog
        onClose={onClose}
        setDialogState={setDialogState}
        currentPrompt={''}
        setCurrentPrompt={setCurrentPrompt}
        promptSuggestionText={''}
        setPromptSuggestionText={setPromptSuggestionText}
        type="system"
      />,
    )

    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Improve prompt'})).toHaveAttribute('disabled')
  })

  it('displays enabled button when currentPrompt is not empty', () => {
    const currentPrompt = 'test'
    render(
      <ImprovePromptDialog
        onClose={onClose}
        setDialogState={setDialogState}
        currentPrompt={currentPrompt}
        setCurrentPrompt={setCurrentPrompt}
        promptSuggestionText={''}
        setPromptSuggestionText={setPromptSuggestionText}
        type="system"
      />,
    )

    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Improve prompt'})).not.toHaveAttribute('disabled')
  })

  it('can type specific suggestions and open a confirmation dialog', async () => {
    const currentPrompt = 'test'
    const {user} = render(
      <ImprovePromptDialog
        onClose={onClose}
        setDialogState={setDialogState}
        currentPrompt={currentPrompt}
        setCurrentPrompt={setCurrentPrompt}
        promptSuggestionText={''}
        setPromptSuggestionText={setPromptSuggestionText}
        type="system"
      />,
    )

    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()

    const textbox = screen.getByRole('textbox', {name: 'What would you like to improve? (optional)'})
    await user.type(textbox, 'text')

    expect(setPromptSuggestionText).toHaveBeenCalled()

    const button = screen.getByRole('button', {name: 'Improve prompt'})

    await user.click(button)

    expect(setDialogState).toHaveBeenCalledWith('confirm')
    expect(sendEvent).toHaveBeenCalledWith(GenerateSystemPromptClicked)
  })

  it('can type specific suggestions and open a confirmation dialog to improve user prompt', async () => {
    const currentPrompt = 'test'
    const {user} = render(
      <ImprovePromptDialog
        onClose={onClose}
        setDialogState={setDialogState}
        currentPrompt={currentPrompt}
        setCurrentPrompt={setCurrentPrompt}
        promptSuggestionText={''}
        setPromptSuggestionText={setPromptSuggestionText}
        type="user"
      />,
    )

    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()

    const textbox = screen.getByRole('textbox', {name: 'What would you like to improve? (optional)'})
    await user.type(textbox, 'text')

    expect(setPromptSuggestionText).toHaveBeenCalled()

    const button = screen.getByRole('button', {name: 'Improve prompt'})

    await user.click(button)

    expect(setDialogState).toHaveBeenCalledWith('confirm')
    expect(sendEvent).toHaveBeenCalledWith(GenerateUserPromptClicked)
  })

  it('can update current prompt', async () => {
    const currentPrompt = 'test'
    const {user} = render(
      <ImprovePromptDialog
        onClose={onClose}
        setDialogState={setDialogState}
        currentPrompt={currentPrompt}
        setCurrentPrompt={setCurrentPrompt}
        promptSuggestionText={''}
        setPromptSuggestionText={setPromptSuggestionText}
        type="system"
      />,
    )

    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()

    const textbox = screen.getByRole('textbox', {name: 'Current prompt'})
    await user.type(textbox, 'updated text')

    expect(setCurrentPrompt).toHaveBeenCalled()
  })
})
