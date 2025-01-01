import {render as htmlRender, type TestRenderOptions} from '@github-ui/react-core/test-utils'
import {screen, within} from '@testing-library/react'
import {ImprovePrompt} from '../ImprovePrompt'
import {mockShowModelPayload} from '../../../show/components/__tests__/mocks'
import {mockModel} from '../../__tests__/mocks'
import {sendEvent} from '@github-ui/hydro-analytics'
import {
  CancelImprovedSystemPromptClicked,
  CancelImprovedUserPromptClicked,
  ImproveSystemPromptClicked,
  ImproveUserPromptClicked,
  UseImprovedSystemPromptClicked,
  UseImprovedUserPromptClicked,
} from '../../../../utils/playground-types'
import {ModelClientProvider} from '../../contexts/ModelClientContext'
import type {JSX} from 'react/jsx-runtime'
import {AzureModelClient} from '../../../../utils/azure-model-client'

jest.mock('@github-ui/hydro-analytics', () => {
  return {
    sendEvent: jest.fn(),
  }
})
const handleUpdatePrompt = jest.fn().mockName('handleUpdatePrompt')
const routePayload = mockShowModelPayload({improvedPromptModel: mockModel})

describe('ImprovePrompt2', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  test('renders the improve prompt button', () => {
    render(<ImprovePrompt prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />, {routePayload})

    expect(screen.getByRole('button', {name: /Improve prompt/i})).toBeInTheDocument()
  })

  test('renders the improve prompt icon in the user prompt', () => {
    render(<ImprovePrompt type="user" prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />, {
      routePayload,
    })

    expect(screen.getByLabelText('Open improve prompt dialog')).toBeInTheDocument()
  })

  it('does not render the improve prompt button when improvedPromptModel is nill', () => {
    render(<ImprovePrompt prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />)
    expect(screen.queryByRole('button', {name: /Improve prompt/i})).not.toBeInTheDocument()
  })

  it('does not render the improve prompt icon when improvedPromptModel is nill', () => {
    render(<ImprovePrompt type="user" prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />)
    expect(screen.queryByLabelText('Open improve prompt dialog')).not.toBeInTheDocument()
  })

  test('when user clicks the improve prompt button, the dialog opens', async () => {
    const {user} = render(<ImprovePrompt prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />, {
      routePayload,
    })

    const button = screen.getByRole('button', {name: /Improve prompt/i})
    await user.click(button)

    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()
    expect(sendEvent).toHaveBeenCalledWith(ImproveSystemPromptClicked)
  })

  test('when user clicks the improve prompt icon, the dialog opens', async () => {
    const {user} = render(
      <ImprovePrompt type="user" prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />,
      {
        routePayload,
      },
    )

    const icon = screen.getByLabelText('Open improve prompt dialog')
    await user.click(icon)

    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()
    expect(sendEvent).toHaveBeenCalledWith(ImproveUserPromptClicked)
  })

  test('when user clicks the cancel button, the dialog to improve system prompt closes', async () => {
    const {user} = render(<ImprovePrompt prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />, {
      routePayload,
    })

    const button = screen.getByRole('button', {name: /Improve prompt/i})
    await user.click(button)

    const cancelButton = screen.getByRole('button', {name: 'Cancel'})
    await user.click(cancelButton)

    expect(screen.queryByTestId('prompt-dialog')).not.toBeInTheDocument()
  })

  test('when user clicks the cancel button, the dialog to improve user prompt closes', async () => {
    const {user} = render(
      <ImprovePrompt type="user" prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />,
      {
        routePayload,
      },
    )

    const icon = screen.getByLabelText('Open improve prompt dialog')
    await user.click(icon)

    const cancelButton = screen.getByRole('button', {name: 'Cancel'})
    await user.click(cancelButton)

    expect(screen.queryByTestId('prompt-dialog')).not.toBeInTheDocument()
  })

  test('sends CancelImprovedSystemPromptClicked event when confirmation dialog is closed', async () => {
    const {user} = render(<ImprovePrompt prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />, {
      routePayload,
    })

    const button = screen.getAllByRole('button', {name: /Improve prompt/i})[0] as HTMLButtonElement
    await user.click(button)

    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()

    const dialog = screen.getByRole('dialog')

    const firstDialogButton = within(dialog).getByRole('button', {name: 'Improve prompt'})
    expect(firstDialogButton).toBeInTheDocument()
    await user.click(firstDialogButton)

    expect(screen.getByTestId('prompt-dialog-confirmation')).toBeInTheDocument()

    const cancelButton = screen.getByRole('button', {name: 'Cancel'})
    await user.click(cancelButton)

    expect(sendEvent).toHaveBeenCalledWith(CancelImprovedSystemPromptClicked)
  })

  test('sends CancelImprovedUserPromptClicked event when confirmation dialog is closed', async () => {
    const {user} = render(
      <ImprovePrompt type="user" prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />,
      {
        routePayload,
      },
    )

    const icon = screen.getByLabelText('Open improve prompt dialog')
    await user.click(icon)

    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()

    const dialog = screen.getByRole('dialog')

    const firstDialogButton = within(dialog).getByRole('button', {name: 'Improve prompt'})
    expect(firstDialogButton).toBeInTheDocument()
    await user.click(firstDialogButton)

    expect(screen.getByTestId('prompt-dialog-confirmation')).toBeInTheDocument()

    const cancelButton = screen.getByRole('button', {name: 'Cancel'})
    await user.click(cancelButton)

    expect(sendEvent).toHaveBeenCalledWith(CancelImprovedUserPromptClicked)
  })

  it('sends UseImprovedSystemPromptClicked event when using generated system prompt', async () => {
    const {user} = render(<ImprovePrompt prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />, {
      routePayload,
    })

    const button = screen.getAllByRole('button', {name: /Improve prompt/i})[0] as HTMLButtonElement
    await user.click(button)
    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()

    const dialog = screen.getByRole('dialog')
    const firstDialogButton = within(dialog).getByRole('button', {name: 'Improve prompt'})
    await user.click(firstDialogButton)

    expect(screen.getByTestId('prompt-dialog-confirmation')).toBeInTheDocument()

    const useImprovedPromptButton = screen.getByRole('button', {name: 'Use improved prompt'})
    await user.click(useImprovedPromptButton)

    expect(sendEvent).toHaveBeenCalledWith(UseImprovedSystemPromptClicked)
  })

  it('sends UseImprovedUserPromptClicked event when using generated user prompt', async () => {
    const {user} = render(
      <ImprovePrompt type="user" prompt="This is a prompt" handleUpdatePrompt={handleUpdatePrompt} />,
      {
        routePayload,
      },
    )

    const icon = screen.getByLabelText('Open improve prompt dialog')
    await user.click(icon)
    expect(screen.getByTestId('prompt-dialog')).toBeInTheDocument()

    const dialog = screen.getByRole('dialog')
    const firstDialogButton = within(dialog).getByRole('button', {name: 'Improve prompt'})
    await user.click(firstDialogButton)

    expect(screen.getByTestId('prompt-dialog-confirmation')).toBeInTheDocument()

    const useImprovedPromptButton = screen.getByRole('button', {name: 'Use improved prompt'})
    await user.click(useImprovedPromptButton)

    expect(sendEvent).toHaveBeenCalledWith(UseImprovedUserPromptClicked)
  })

  function render(component: JSX.Element, opts?: TestRenderOptions) {
    const playgroundUrl = 'azure-ai-playground-url.com'
    const mockModelClient = new AzureModelClient(playgroundUrl)
    return htmlRender(<ModelClientProvider modelClient={mockModelClient}>{component}</ModelClientProvider>, opts)
  }
})
