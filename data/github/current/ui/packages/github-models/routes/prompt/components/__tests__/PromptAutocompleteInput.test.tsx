import {render} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'
import {PromptAutocompleteInput} from '../PromptAutocompleteInput'
import {mockPromptEvalsState} from './mocks'
import {PromptEvalsManagerContext, type PromptEvalsManager} from '../../prompt-evals-manager'
import {PromptEvalsStateProvider} from '../../contexts/PromptEvalsStateContext'
import {ModelClientProvider} from '../../../playground/contexts/ModelClientContext'
import {AzureModelClient} from '../../../../utils/azure-model-client'
import {mockShowModelPayload} from '../../../show/components/__tests__/mocks'
import {mockModel} from '../../../playground/__tests__/mocks'

const setPromptInput = jest.fn().mockName('setPromptInput')

describe('PromptAutocompleteInput', () => {
  test('renders with correct placeholder', () => {
    renderComponent(
      <PromptAutocompleteInput
        label="User"
        prompt=""
        setPromptInput={setPromptInput}
        variableKeys={[]}
        textareaPlaceholder="Enter your prompt"
      />,
    )

    const textarea = screen.getByRole('textbox', {name: 'User'})
    expect(screen.getByTestId('stylized-input')).toBeInTheDocument()
    expect(textarea).toBeInTheDocument()
    expect(textarea).toHaveAttribute('placeholder', 'Enter your prompt')
  })

  test('renders with prompt and textarea and stylized input have same text', () => {
    renderComponent(
      <PromptAutocompleteInput
        label="User"
        prompt="This is a prompt"
        setPromptInput={setPromptInput}
        variableKeys={[]}
        textareaPlaceholder="Enter your prompt"
      />,
    )

    const textarea = screen.getByRole('textbox', {name: 'User'})
    const stylizedInput = screen.getByTestId('stylized-input')
    expect(textarea).toBeInTheDocument()
    expect(stylizedInput).toBeInTheDocument()

    expect(textarea).toHaveTextContent('This is a prompt')
    expect(stylizedInput).toHaveTextContent('This is a prompt')
  })

  test('renders with highlighted variable in stylized input', () => {
    renderComponent(
      <PromptAutocompleteInput
        label="User"
        prompt="This is a prompt with a {{variable}}"
        setPromptInput={setPromptInput}
        variableKeys={[]}
        textareaPlaceholder="Enter your prompt"
      />,
    )

    const textarea = screen.getByRole('textbox', {name: 'User'})
    const stylizedInput = screen.getByTestId('stylized-input')
    expect(textarea).toBeInTheDocument()
    expect(stylizedInput).toBeInTheDocument()

    expect(textarea).toHaveTextContent('This is a prompt with a {{variable}}')
    expect(screen.getByTestId('variable-highlight-{{variable}}-1')).toBeInTheDocument()
  })

  test('when user types in textarea, calls setPromptInput', async () => {
    const {user} = renderComponent(
      <PromptAutocompleteInput
        label="User"
        prompt="This is a prompt"
        setPromptInput={setPromptInput}
        variableKeys={[]}
        textareaPlaceholder="Enter your prompt"
      />,
    )

    const textarea = screen.getByRole('textbox', {name: 'User'})
    expect(textarea).toBeInTheDocument()
    await user.type(textarea, 's')

    expect(setPromptInput).toHaveBeenCalledTimes(1)
    expect(setPromptInput).toHaveBeenCalledWith('This is a prompts')
  })

  test('renders improve prompt button when showImprovePrompt is true', () => {
    renderComponent(
      <PromptAutocompleteInput
        label="User"
        prompt="This is a prompt"
        setPromptInput={setPromptInput}
        variableKeys={[]}
        textareaPlaceholder="Enter your prompt"
        showImprovePrompt
      />,
    )

    expect(screen.getByRole('button', {name: /Improve prompt/i})).toBeInTheDocument()
  })

  test('does not render improve prompt button when showImprovePrompt is false', () => {
    renderComponent(
      <PromptAutocompleteInput
        label="User"
        prompt="This is a prompt"
        setPromptInput={setPromptInput}
        variableKeys={[]}
        textareaPlaceholder="Enter your prompt"
      />,
    )

    expect(screen.queryByRole('button', {name: /Improve prompt/i})).not.toBeInTheDocument()
  })

  function renderComponent(component: JSX.Element) {
    const playgroundUrl = 'azure-ai-playground-url.com'
    const mockModelClient = new AzureModelClient(playgroundUrl)
    const routePayload = mockShowModelPayload({improvedPromptModel: mockModel})

    const initialState = mockPromptEvalsState()
    const manager = {} as PromptEvalsManager
    manager.setPromptInput = setPromptInput

    return render(
      <ModelClientProvider modelClient={mockModelClient}>
        <PromptEvalsStateProvider state={initialState}>
          <PromptEvalsManagerContext.Provider value={manager}>{component}</PromptEvalsManagerContext.Provider>
        </PromptEvalsStateProvider>
      </ModelClientProvider>,
      {routePayload},
    )
  }
})
