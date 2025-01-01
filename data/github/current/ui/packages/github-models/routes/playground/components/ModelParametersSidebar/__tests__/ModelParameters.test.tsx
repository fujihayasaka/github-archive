import {render as htmlRender} from '@github-ui/react-core/test-utils'
import {mockModelState, mockO1ModelState} from '../../../__tests__/mocks'
import ModelParameters from '../ModelParameters'
import {screen, within} from '@testing-library/react'
import type {PlaygroundManager} from '../../../../../utils/playground-manager'
import {PlaygroundManagerProvider} from '../../../../../contexts/PlaygroundManagerContext'
import {PlaygroundStateProvider} from '../../../../../contexts/PlaygroundStateContext'
import {mockPlaygroundState} from '../../__tests__/mocks'

describe('ModelParameters', () => {
  it('renders no parameters and system prompt when they are not available', () => {
    const clonedMockModelState = {
      ...mockModelState,
      modelInputSchema: {...mockModelState.modelInputSchema, parameters: []},
    }
    const handleModelParamsChange = jest.fn()
    render(<ModelParameters model={clonedMockModelState} handleModelParamsChange={handleModelParamsChange} />)

    expect(screen.getByText('No parameters available')).toBeInTheDocument()
    expect(screen.queryByLabelText('System Prompt')).not.toBeInTheDocument()
  })

  it('renders system prompt when available', async () => {
    const clonedMockModelState = {
      ...mockModelState,
      modelInputSchema: {...mockModelState.modelInputSchema, capabilities: {systemPrompt: true}},
    }
    const handleModelParamsChange = jest.fn()
    const handleSystemPromptChange = jest.fn()
    const updateSystemPrompt = jest.fn()

    const {user} = render(
      <ModelParameters
        model={clonedMockModelState}
        handleModelParamsChange={handleModelParamsChange}
        handleSystemPromptChange={handleSystemPromptChange}
        updateSystemPrompt={updateSystemPrompt}
      />,
    )

    const systemPromptInput = screen.getByRole('textbox', {name: 'System prompt'})
    expect(systemPromptInput).toBeInTheDocument()
    await user.type(systemPromptInput, 'test')
    expect(handleSystemPromptChange).toHaveBeenCalled()
  })

  it('renders parameters when available', () => {
    const handleModelParamsChange = jest.fn()
    render(<ModelParameters model={mockModelState} handleModelParamsChange={handleModelParamsChange} />)

    expect(screen.getByLabelText('stop')).toBeInTheDocument()
    expect(screen.getByLabelText('top_p')).toBeInTheDocument()
    expect(screen.getByLabelText('temperature')).toBeInTheDocument()
    expect(screen.getByLabelText('max_tokens')).toBeInTheDocument()
  })

  it('renders multiple-choice parameters when available', async () => {
    const handleModelParamsChange = jest.fn()
    render(<ModelParameters model={mockO1ModelState} handleModelParamsChange={handleModelParamsChange} />)

    expect(screen.getByLabelText('stop')).toBeInTheDocument()
    expect(screen.getByLabelText('top_p')).toBeInTheDocument()
    expect(screen.getByLabelText('temperature')).toBeInTheDocument()
    expect(screen.getByLabelText('max_tokens')).toBeInTheDocument()
    const responseFormatControl = await screen.findByRole('button', {name: 'reasoning_effort'})
    expect(responseFormatControl).toBeInTheDocument()
  })

  it('renders the response format radio buttons for text and json but not schema if not on single playground view', () => {
    const handleModelParamsChange = jest.fn()
    const handleResponseFormatChange = jest.fn()
    const handleJsonSchemaChange = jest.fn()
    render(
      <ModelParameters
        model={mockModelState}
        handleModelParamsChange={handleModelParamsChange}
        handleResponseFormatChange={handleResponseFormatChange}
        handleJsonSchemaChange={handleJsonSchemaChange}
      />,
    )

    const responseFormatGroup = screen.getByTestId('response-format')
    expect(responseFormatGroup).toBeInTheDocument()

    const responseFormatRadioGroup = within(responseFormatGroup).getByRole('group')
    expect(responseFormatRadioGroup).toHaveTextContent('Response format')

    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'Text'})).toHaveAttribute('aria-checked', 'true')
    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'JSON'})).toHaveAttribute('aria-checked', 'false')
    expect(within(responseFormatRadioGroup).queryByRole('radio', {name: 'Schema'})).not.toBeInTheDocument()
  })

  it('renders the response format radio buttons for schema for GPT-4o on single playground view', () => {
    const clonedMockModelState = {
      ...mockModelState,
      catalogData: {...mockModelState.catalogData, name: 'gpt-4o'},
    }

    const handleModelParamsChange = jest.fn()
    const handleResponseFormatChange = jest.fn()
    const handleJsonSchemaChange = jest.fn()
    render(
      <ModelParameters
        model={clonedMockModelState}
        handleModelParamsChange={handleModelParamsChange}
        handleResponseFormatChange={handleResponseFormatChange}
        handleJsonSchemaChange={handleJsonSchemaChange}
        onSinglePlaygroundView
      />,
    )

    const responseFormatGroup = screen.getByTestId('response-format')
    expect(responseFormatGroup).toBeInTheDocument()

    const responseFormatRadioGroup = within(responseFormatGroup).getByRole('group')
    expect(responseFormatRadioGroup).toHaveTextContent('Response format')

    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'Text'})).toHaveAttribute('aria-checked', 'true')
    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'JSON'})).toHaveAttribute('aria-checked', 'false')
    expect(within(responseFormatRadioGroup).getByRole('radio', {name: 'Schema'})).toHaveAttribute(
      'aria-checked',
      'false',
    )
  })
})

function render(component: JSX.Element, manager?: PlaygroundManager) {
  return htmlRender(
    <PlaygroundManagerProvider manager={manager ?? ({} as PlaygroundManager)}>
      <PlaygroundStateProvider state={mockPlaygroundState()}>{component}</PlaygroundStateProvider>
    </PlaygroundManagerProvider>,
  )
}
