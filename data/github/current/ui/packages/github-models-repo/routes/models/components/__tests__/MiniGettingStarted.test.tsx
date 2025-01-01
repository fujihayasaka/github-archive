import {render} from '@github-ui/react-core/test-utils'
import {act, screen} from '@testing-library/react'
import {MiniGettingStarted, replaceParameters} from '../MiniGettingStarted'
import {mockGettingStarted, mockModel} from './mocks'
import {getModelRepoPromptsAppPayload} from '../../../../test-utils/mock-data'
import {ThemeProvider} from '@primer/react'

const model = mockModel('model-1')
const model2 = mockModel('model-2')

const mockUseFilteredModels = jest.fn().mockName('useFilteredModels')
const mockUseQuery = jest.fn().mockName('useQuery')

jest.mock('../../../../hooks/use-filtered-models', () => ({useFilteredModels: () => mockUseFilteredModels()}))
jest.mock('@github-ui/react-query', () => ({useQuery: () => mockUseQuery()}))
jest.mock('@github-ui/github-models/GettingStartedDialog', () => ({
  __esModule: true,
  default: (props: any) => (
    <button data-testid="getting-started-dialog" onClick={props.onClose}>
      Fake Getting Started
    </button>
  ),
}))

const setShowDialog = jest.fn()

describe('MiniGettingStarted', () => {
  beforeEach(() => {
    mockUseFilteredModels.mockReturnValue({
      availableModels: [model, model2],
      isLoadingModels: false,
    })
    mockUseQuery.mockReturnValue({data: mockGettingStarted()})
  })

  test('renders header and Get API Key button', () => {
    const appPayload = getModelRepoPromptsAppPayload()

    render(<MiniGettingStarted showDialog={false} setShowDialog={setShowDialog} />, {appPayload})

    expect(screen.getByText('Add AI to your project now')).toBeInTheDocument()
    expect(screen.getByText('Drop this snippet into your code to start using AI instantly.')).toBeInTheDocument()

    const getApiKeyButton = screen.getByText('Get API Key')
    expect(getApiKeyButton).toBeInTheDocument()
    getApiKeyButton.click()
    expect(setShowDialog).toHaveBeenCalledWith(true)
  })

  test('renders loading state when models are loading', () => {
    const appPayload = getModelRepoPromptsAppPayload()
    mockUseFilteredModels.mockReturnValue({
      availableModels: [],
      isLoadingModels: true,
    })

    render(<MiniGettingStarted showDialog={false} setShowDialog={setShowDialog} />, {appPayload})

    expect(screen.getByText('Loading')).toBeInTheDocument()
  })

  test('auto selects first model, language, and sdk when available models are loaded', () => {
    const appPayload = getModelRepoPromptsAppPayload()

    render(<MiniGettingStarted showDialog={false} setShowDialog={setShowDialog} />, {appPayload})

    expect(screen.getByText('model-1-friendly')).toBeInTheDocument()
    expect(screen.getByText('Python')).toBeInTheDocument()
    expect(screen.getByText('Azure Python SDK')).toBeInTheDocument()
    expect(screen.getByText('azure-python-sdk code sample')).toBeInTheDocument()
  })

  test('changes model when new model is selected', async () => {
    const appPayload = getModelRepoPromptsAppPayload()

    render(<MiniGettingStarted showDialog={false} setShowDialog={setShowDialog} />, {appPayload})

    expect(screen.getByText('model-1-friendly')).toBeInTheDocument()
    expect(screen.queryByText('model-2-friendly')).not.toBeInTheDocument()

    await act(async () => {
      screen.getByText('model-1-friendly').click()
    })
    await act(async () => {
      screen.getByText('model-2-friendly').click()
    })

    expect(screen.queryByText('model-1-friendly')).not.toBeInTheDocument()
    expect(screen.getByText('model-2-friendly')).toBeInTheDocument()
  })

  test('changes language and sdk when new language is selected', async () => {
    const appPayload = getModelRepoPromptsAppPayload()

    render(<MiniGettingStarted showDialog={false} setShowDialog={setShowDialog} />, {
      appPayload,
      wrapper: ThemeProvider,
    }) // ThemeProvider needed as ActionList uses Overlay

    expect(screen.getByText('Python')).toBeInTheDocument()
    expect(screen.getByText('Azure Python SDK')).toBeInTheDocument()
    expect(screen.queryByText('JavaScript')).not.toBeInTheDocument()
    expect(screen.queryByText('Azure JavaScript SDK')).not.toBeInTheDocument()

    await act(async () => {
      screen.getByText('Python').click()
    })
    await act(async () => {
      screen.getByText('JavaScript').click()
    })

    await screen.findByText('JavaScript')
    await screen.findByText('Azure JavaScript SDK')

    expect(screen.queryByText('Python')).not.toBeInTheDocument()
    expect(screen.queryByText('Azure Python SDK')).not.toBeInTheDocument()
    expect(screen.getByText('JavaScript')).toBeInTheDocument()
    expect(screen.getByText('Azure JavaScript SDK')).toBeInTheDocument()
  })

  test('changes sdk when new sdk is selected', async () => {
    const appPayload = getModelRepoPromptsAppPayload()

    render(<MiniGettingStarted showDialog={false} setShowDialog={setShowDialog} />, {
      appPayload,
      wrapper: ThemeProvider,
    }) // ThemeProvider needed as ActionList uses Overlay

    expect(screen.getByText('Azure Python SDK')).toBeInTheDocument()
    expect(screen.queryByText('Azure Python SDK 2')).not.toBeInTheDocument()

    await act(async () => {
      screen.getByText('Azure Python SDK').click()
    })
    await act(async () => {
      screen.getByText('Azure Python SDK 2').click()
    })

    expect(screen.queryByText('Azure Python SDK')).not.toBeInTheDocument()
    expect(screen.getByText('Azure Python SDK 2')).toBeInTheDocument()
  })

  test('shows dialog when showDialog is true', () => {
    const appPayload = getModelRepoPromptsAppPayload()

    render(<MiniGettingStarted showDialog setShowDialog={setShowDialog} />, {appPayload})

    const dialog = screen.getByTestId('getting-started-dialog')
    expect(dialog).toBeInTheDocument()
    dialog.click()
    expect(setShowDialog).toHaveBeenCalledWith(false)
  })

  test('toggles code expansion when Show more/less button is clicked', async () => {
    const appPayload = getModelRepoPromptsAppPayload()

    render(<MiniGettingStarted showDialog={false} setShowDialog={setShowDialog} />, {appPayload})

    expect(screen.getByText('Show more')).toBeInTheDocument()
    expect(screen.queryByText('Show less')).not.toBeInTheDocument()

    await act(async () => {
      screen.getByText('Show more').click()
    })

    expect(screen.getByText('Show less')).toBeInTheDocument()
    expect(screen.queryByText('Show more')).not.toBeInTheDocument()
    await act(async () => {
      screen.getByText('Show less').click()
    })

    expect(screen.getByText('Show more')).toBeInTheDocument()
    expect(screen.queryByText('Show less')).not.toBeInTheDocument()
  })

  test('replaceParameters function replaces parameters in code snippet', () => {
    const snippetTemplate =
      '"""Run this model in Python\r\n\r\n> pip install azure-ai-inference\r\n"""\r\nimport os\r\nfrom azure.ai.inference import ChatCompletionsClient\r\nfrom azure.ai.inference.models import SystemMessage\r\nfrom azure.ai.inference.models import UserMessage\r\nfrom azure.core.credentials import AzureKeyCredential\r\n\r\n# To authenticate with the model you will need to generate a personal access token (PAT) in your GitHub settings. \r\n# Create your PAT token by following instructions here: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens\r\nclient = ChatCompletionsClient(\r\n    endpoint="{model_endpoint}",\r\n    credential=AzureKeyCredential(os.environ["GITHUB_TOKEN"]),\r\n)\r\n\r\nresponse = client.complete(\r\n    messages=[\r\n        SystemMessage("""{system_message}"""),\r\n        UserMessage("Can you explain the basics of machine learning?"),\r\n    ],\r\n    model="{model_name}",\r\n    temperature={temperature},\r\n    max_tokens={max_tokens},\r\n    top_p={top_p}\r\n)\r\n\r\nprint(response.choices[0].message.content)\r\n'

    const snippet = replaceParameters(snippetTemplate, model)

    expect(snippet).toContain(`${model?.publisherSlug}/${model?.original_name}`)
    expect(snippet).toContain('https://models.github.ai/inference')
    expect(snippet).toContain('You are a helpful assistant.')
    expect(snippet).toContain('1.0')
    expect(snippet).toContain('1000')
    expect(snippet).toContain('1.0')

    expect(snippet).not.toContain('{model_name}')
    expect(snippet).not.toContain('{system_message}')
    expect(snippet).not.toContain('{model_endpoint}')
    expect(snippet).not.toContain('{temperature}')
    expect(snippet).not.toContain('{max_tokens}')
    expect(snippet).not.toContain('{top_p}')
  })
})
