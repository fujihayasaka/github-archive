import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {mockModel} from '../../__tests__/mocks'
import {ImprovePromptConfirmationDialog} from '../ImprovePromptConfirmationDialog'
import {ModelClientProvider} from '../../contexts/ModelClientContext'
import {AzureModelClient} from '../../../../utils/azure-model-client'

const generatedPrompt = 'updated text'
jest.mock('../../hooks/use-improve-prompt', () => ({
  useImprovePrompt: jest.fn(() => ({generatedPrompt, isLoading: true})),
}))

describe('ImprovePromptConfirmationDialog', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })
  const onClose = jest.fn()
  const handleUpdatePrompt = jest.fn()
  const setImprovedPromptText = jest.fn()
  const setDialogState = jest.fn()
  const promptSuggestionText = 'provide a detailed response'
  const currentPrompt = 'respond in one sentence'

  it('renders a spinner and current prompt', async () => {
    const improvedPromptText = 'text'
    render(
      <ImprovePromptConfirmationDialog
        onClose={onClose}
        handleUpdatePrompt={handleUpdatePrompt}
        promptSuggestionText={promptSuggestionText}
        currentPrompt={currentPrompt}
        improvedPromptText={improvedPromptText}
        setImprovedPromptText={setImprovedPromptText}
        improvedPromptModel={mockModel}
        setDialogState={setDialogState}
        type="system"
      />,
    )

    expect(screen.getByTestId('prompt-dialog-confirmation')).toBeInTheDocument()
    expect(screen.getByRole('textbox')).toHaveValue(improvedPromptText)
    expect(screen.getByLabelText('Loading improved prompt')).toBeInTheDocument()
    expect(setImprovedPromptText).toHaveBeenCalledWith(generatedPrompt)
    expect(screen.getByRole('button', {name: 'Cancel'})).toBeInTheDocument()
    expect(screen.getByRole('button', {name: 'Use improved prompt'})).toBeInTheDocument()
  })

  it('can close ImprovePromptConfirmationDialog', async () => {
    const improvedPromptText = 'text'
    const {user} = render(
      <ImprovePromptConfirmationDialog
        onClose={onClose}
        handleUpdatePrompt={handleUpdatePrompt}
        promptSuggestionText={promptSuggestionText}
        currentPrompt={currentPrompt}
        improvedPromptText={improvedPromptText}
        setImprovedPromptText={setImprovedPromptText}
        improvedPromptModel={mockModel}
        setDialogState={setDialogState}
        type="system"
      />,
    )

    expect(screen.getByTestId('prompt-dialog-confirmation')).toBeInTheDocument()

    const cancel = screen.getByRole('button', {name: 'Cancel'})
    await user.click(cancel)

    expect(onClose).toHaveBeenCalled()
  })

  it('can go back to the previous dialog', async () => {
    const improvedPromptText = 'text'
    const {user} = render(
      <ImprovePromptConfirmationDialog
        onClose={onClose}
        handleUpdatePrompt={handleUpdatePrompt}
        promptSuggestionText={promptSuggestionText}
        currentPrompt={currentPrompt}
        improvedPromptText={improvedPromptText}
        setImprovedPromptText={setImprovedPromptText}
        improvedPromptModel={mockModel}
        setDialogState={setDialogState}
        type="system"
      />,
    )

    expect(screen.getByTestId('prompt-dialog-confirmation')).toBeInTheDocument()

    const back = screen.getByRole('button', {name: 'Back'})
    await user.click(back)

    expect(setDialogState).toHaveBeenCalledWith('suggest')
  })

  it('can modify the improved prompt and update the current system prompt', async () => {
    const improvedPromptText = ''
    const {user} = render(
      <ImprovePromptConfirmationDialog
        onClose={onClose}
        handleUpdatePrompt={handleUpdatePrompt}
        promptSuggestionText={promptSuggestionText}
        currentPrompt={currentPrompt}
        improvedPromptText={improvedPromptText}
        setImprovedPromptText={setImprovedPromptText}
        improvedPromptModel={mockModel}
        setDialogState={setDialogState}
        type="system"
      />,
    )

    expect(screen.getByTestId('prompt-dialog-confirmation')).toBeInTheDocument()
    const textbox = screen.getByRole('textbox')
    expect(textbox).toHaveValue(improvedPromptText)

    expect(setImprovedPromptText).toHaveBeenCalledWith('updated text')

    await user.type(textbox, 'hi')

    expect(setImprovedPromptText).toHaveBeenCalledTimes(3)

    const button = screen.getByRole('button', {name: 'Use improved prompt'})

    await user.click(button)

    expect(handleUpdatePrompt).toHaveBeenCalled()
  })
})

function render(component: JSX.Element) {
  const playgroundUrl = 'azure-ai-playground-url.com'
  const mockModelClient = new AzureModelClient(playgroundUrl)
  return htmlRender(<ModelClientProvider modelClient={mockModelClient}>{component}</ModelClientProvider>)
}
