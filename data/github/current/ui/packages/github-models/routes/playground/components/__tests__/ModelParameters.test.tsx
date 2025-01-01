import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {mockModelState} from '../../__tests__/mocks'
import ModelParameters from '../ModelParameters'
import {screen, within} from '@testing-library/react'
import {PlaygroundManagerContext, type PlaygroundManager} from '../../../../utils/playground-manager'
import {PlaygroundStateProvider} from '../../../../contexts/PlaygroundStateContext'
import {mockPlaygroundState} from './mocks'
import {useFeatureFlag} from '@github-ui/react-core/use-feature-flag'

jest.mock('@github-ui/react-core/use-feature-flag')

const mockUseFeatureFlag = jest.mocked(useFeatureFlag)

describe('ModelParameters', () => {
  it('renders no parameters and system prompt when they are not available', () => {
    const clonedMockModelState = {
      ...mockModelState,
      modelInputSchema: {...mockModelState.modelInputSchema, parameters: []},
    }
    render(<ModelParameters model={clonedMockModelState} position={0} />)

    expect(screen.getByText('No parameters available')).toBeInTheDocument()
    expect(screen.queryByTestId('model-parameters-system-prompt')).not.toBeInTheDocument()
  })

  it('renders system prompt when available', async () => {
    const manager = {} as PlaygroundManager
    manager.setSystemPrompt = jest.fn()
    manager.setParametersHasChanges = jest.fn()
    const clonedMockModelState = {
      ...mockModelState,
      modelInputSchema: {...mockModelState.modelInputSchema, capabilities: {systemPrompt: true}},
    }
    const {user} = render(<ModelParameters model={clonedMockModelState} position={0} />, manager)

    const systemPromptInput = screen.getByRole('textbox', {name: 'System prompt'})
    expect(systemPromptInput).toBeInTheDocument()
    await user.type(systemPromptInput, 'test')
    expect(manager.setSystemPrompt).toHaveBeenCalled()
    expect(manager.setParametersHasChanges).toHaveBeenCalledTimes(4)
  })

  it('renders parameters when available', async () => {
    render(<ModelParameters model={mockModelState} position={0} />)

    expect(screen.getByLabelText('stop')).toBeInTheDocument()
    expect(screen.getByLabelText('top_p')).toBeInTheDocument()
    expect(screen.getByLabelText('temperature')).toBeInTheDocument()
    expect(screen.getByLabelText('max_tokens')).toBeInTheDocument()
  })

  it('renders the response format toggle with accessible labels', async () => {
    mockUseFeatureFlag.mockReturnValue(true)

    render(<ModelParameters model={mockModelState} position={0} />)

    const responseFormatControl = await screen.findByTestId('response-format')

    expect(responseFormatControl).toHaveAccessibleName('Response format')
    expect(within(responseFormatControl).getByRole('button', {name: 'Text'})).toHaveAttribute('aria-current', 'true')
    expect(within(responseFormatControl).getByRole('button', {name: 'JSON'})).not.toHaveAttribute(
      'aria-current',
      'true',
    )
  })
})

function render(component: JSX.Element, manager?: PlaygroundManager) {
  return htmlRender(
    <PlaygroundManagerContext.Provider value={manager ?? ({} as PlaygroundManager)}>
      <PlaygroundStateProvider state={mockPlaygroundState()}>{component}</PlaygroundStateProvider>
    </PlaygroundManagerContext.Provider>,
  )
}
