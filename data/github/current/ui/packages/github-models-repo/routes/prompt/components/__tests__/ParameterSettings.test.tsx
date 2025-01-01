import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {AppPayloadContext} from '@github-ui/react-core/use-app-payload'
import {render, screen} from '@testing-library/react'
import {type PropsWithChildren, useMemo, useReducer} from 'react'
import {getPromptAppPayload, mockModel} from '../../../../test-utils/mock-data'
import {ModelsProvider} from '../../contexts/ModelsContext'
import {initialPromptCompareState, PromptCompareStateProvider} from '../../contexts/PromptCompareStateContext'
import {useModelDetailsQuery} from '../../hooks/use-model-details-query'
import {PromptCompareManager, PromptCompareManagerContext, promptCompareReducer} from '../../prompt-compare-manager'
import ParameterSettings from '../ParameterSettings'

// Mock the `useModelDetailsQuery` hook
jest.mock('../../hooks/use-model-details-query', () => ({
  useModelDetailsQuery: jest.fn(),
}))

const mockSetIsParametersOpen = jest.fn()
const mockSetParameters = jest.fn()
const mockSetResponseFormat = jest.fn()
const mockModelParameters = {key: 'string'}
const mockSetJsonSchema = jest.fn()

describe('ParameterSettings', () => {
  beforeEach(() => {
    ;(useModelDetailsQuery as jest.Mock).mockReturnValue({
      data: {
        modelInputSchema: {
          parameters: [
            {key: 'param1', default: 'default1'},
            {key: 'param2', default: 'default2'},
          ],
        },
      },
    })
  })

  afterEach(() => {
    jest.clearAllMocks()
  })

  it('shows response format for text and json when publisher supports it', () => {
    const model = mockModel({publisher: 'openai', capabilities: {structuredOutput: true}})

    render(
      <PromptWrapper>
        <ParameterSettings
          model={model}
          modelParameters={mockModelParameters}
          isParametersOpen
          setIsParametersOpen={mockSetIsParametersOpen}
          setParameters={mockSetParameters}
          setResponseFormat={mockSetResponseFormat}
          setJsonSchema={mockSetJsonSchema}
          responseFormat={'text'}
          jsonSchema={''}
        />
      </PromptWrapper>,
    )

    expect(screen.getByText('Response format')).toBeInTheDocument()
    expect(screen.getByRole('radio', {name: 'Text'})).toBeInTheDocument()
    expect(screen.getByRole('radio', {name: 'JSON'})).toBeInTheDocument()
    expect(screen.queryByRole('radio', {name: 'JSON Schema'})).not.toBeInTheDocument()
  })

  it('shows JSON Schema option when model supports it', () => {
    const model = mockModel({name: 'gpt-4o', publisher: 'openai', capabilities: {structuredOutput: true}})

    render(
      <PromptWrapper>
        <ParameterSettings
          model={model}
          modelParameters={mockModelParameters}
          isParametersOpen
          setIsParametersOpen={mockSetIsParametersOpen}
          setParameters={mockSetParameters}
          setResponseFormat={mockSetResponseFormat}
          setJsonSchema={mockSetJsonSchema}
          responseFormat={'text'}
          jsonSchema={''}
        />
      </PromptWrapper>,
    )

    expect(screen.getByText('Response format')).toBeInTheDocument()
    expect(screen.getByRole('radio', {name: 'Text'})).toBeInTheDocument()
    expect(screen.getByRole('radio', {name: 'JSON'})).toBeInTheDocument()
    expect(screen.getByRole('radio', {name: 'Schema'})).toBeInTheDocument()
  })

  it('does not show response format when model does not support it', () => {
    const model = mockModel({name: 'o1-mini'})

    render(
      <PromptWrapper>
        <ParameterSettings
          model={model}
          modelParameters={mockModelParameters}
          isParametersOpen
          setIsParametersOpen={mockSetIsParametersOpen}
          setParameters={mockSetParameters}
        />
      </PromptWrapper>,
    )

    expect(screen.queryByText('Response format')).not.toBeInTheDocument()
  })

  it('shows correct message when parameters are unsupported', () => {
    ;(useModelDetailsQuery as jest.Mock).mockReturnValue({
      data: {
        modelInputSchema: {
          parameters: [],
        },
      },
    })

    const model = mockModel()

    render(
      <PromptWrapper>
        <ParameterSettings
          model={model}
          modelParameters={mockModelParameters}
          isParametersOpen
          setIsParametersOpen={mockSetIsParametersOpen}
          setParameters={mockSetParameters}
        />
      </PromptWrapper>,
    )

    expect(
      screen.getByText('Currently, this model does not support any parameters for customization.'),
    ).toBeInTheDocument()
  })
})

const PromptWrapper = ({children}: PropsWithChildren<{mockUpdatePrompt?: boolean}>) => {
  const repository = createRepository()

  const availableModels = [
    mockModel({id: 'gpt-4o', name: 'gpt-4o', friendly_name: 'gpt-4o', original_name: 'gpt-4o'}),
    mockModel(),
  ]
  const prompts = [
    {
      name: 'Test Prompt',
      messages: [],
    },
  ]

  const [promptCompareState, promptCompareDispatch] = useReducer(
    promptCompareReducer,
    initialPromptCompareState(prompts, {
      compare: {
        isRunning: false,
        rows: [],
        result: [],
        evaluators: [],
        skippedRowIds: new Set<string>(),
      },
    }),
  )

  const appPayload = getPromptAppPayload({payload: {promptPath: '/test-org/test-repo/prompts/new'}})

  const manager = useMemo(() => new PromptCompareManager(promptCompareDispatch), [promptCompareDispatch])

  return (
    <CurrentRepositoryProvider repository={repository}>
      <ModelsProvider models={availableModels}>
        <PromptCompareStateProvider state={promptCompareState}>
          <PromptCompareManagerContext.Provider value={manager}>
            <AppPayloadContext.Provider value={appPayload}>{children}</AppPayloadContext.Provider>
          </PromptCompareManagerContext.Provider>
        </PromptCompareStateProvider>
      </ModelsProvider>
    </CurrentRepositoryProvider>
  )
}
