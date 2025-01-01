import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen} from '@testing-library/react'

import {ModelSystemPrompt} from '../ModelSystemPrompt'
import {mockShowModelPayload} from '../../../show/components/__tests__/mocks'
import {mockModel} from '../../__tests__/mocks'

import {ModelClientProvider} from '../../contexts/ModelClientContext'
import {AzureModelClient} from '../../../../utils/azure-model-client'

jest.mock('@github-ui/react-core/use-feature-flag')

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: jest.fn(),
  }
})

const handleSystemPromptChange = jest.fn().mockName('handleSystemPromptChange')
const updateSystemPrompt = jest.fn().mockName('updateSystemPrompt')

describe('ModelSystemPrompt', () => {
  afterEach(() => {
    jest.clearAllMocks()
  })

  it('renders system prompt', () => {
    render(
      <ModelSystemPrompt
        systemPrompt=""
        handleSystemPromptChange={handleSystemPromptChange}
        updateSystemPrompt={updateSystemPrompt}
      />,
    )

    expect(screen.getByLabelText('System prompt')).toBeInTheDocument()
  })

  it('allows to change system prompt', async () => {
    const {user} = render(
      <ModelSystemPrompt
        systemPrompt=""
        handleSystemPromptChange={handleSystemPromptChange}
        updateSystemPrompt={updateSystemPrompt}
      />,
    )

    const systemPromptInput = screen.getByRole('textbox', {name: 'System prompt'})
    await user.type(systemPromptInput, 'test')
    expect(handleSystemPromptChange).toHaveBeenCalled()
  })

  const systemPrompt = 'This is a system prompt'
  it('renders the improve prompt button', () => {
    const routePayload = mockShowModelPayload({improvedPromptModel: mockModel})

    render(
      <ModelSystemPrompt
        systemPrompt={systemPrompt}
        handleSystemPromptChange={handleSystemPromptChange}
        updateSystemPrompt={updateSystemPrompt}
        onSinglePlaygroundView
      />,
      {routePayload},
    )

    expect(screen.getByRole('button', {name: /Improve prompt/i})).not.toHaveAttribute('disabled')
  })

  it('does not render the improve prompt button when onSinglePlaygroundView is false', () => {
    const routePayload = mockShowModelPayload({improvedPromptModel: mockModel})

    render(
      <ModelSystemPrompt
        systemPrompt={systemPrompt}
        handleSystemPromptChange={handleSystemPromptChange}
        updateSystemPrompt={updateSystemPrompt}
        onSinglePlaygroundView={false}
      />,
      {
        routePayload,
      },
    )

    expect(screen.queryByRole('button', {name: 'Improve prompt'})).not.toBeInTheDocument()
  })
})

function render(component: JSX.Element, opts?: TestRenderOptions) {
  const playgroundUrl = 'azure-ai-playground-url.com'
  const mockModelClient = new AzureModelClient(playgroundUrl)
  return htmlRender(<ModelClientProvider modelClient={mockModelClient}>{component}</ModelClientProvider>, opts)
}
