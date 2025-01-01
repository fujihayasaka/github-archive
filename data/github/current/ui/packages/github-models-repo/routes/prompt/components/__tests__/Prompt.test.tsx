import {render} from '@github-ui/react-core/test-utils'
import {screen, waitFor} from '@testing-library/react'
import {Prompt} from '../Prompt'
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {ModelsProvider} from '../../contexts/ModelsContext'
import {initialPromptCompareState, PromptCompareStateProvider} from '../../contexts/PromptCompareStateContext'
import {PromptCompareManager, PromptCompareManagerContext, promptCompareReducer} from '../../prompt-compare-manager'
import {AzureModelClient} from '@github-ui/github-models/AzureModelClient'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {useMemo, useReducer, type PropsWithChildren} from 'react'
import {AppPayloadContext} from '@github-ui/react-core/use-app-payload'
import {getPromptAppPayload, mockModel} from '../../../../test-utils/mock-data'

const mockModelClient = new AzureModelClient('https://mock-url.com')
const updatePrompt = jest.fn().mockName('updatePrompt')

describe('PromptBlankslate', () => {
  it('renders with default model for new prompt', async () => {
    render(
      <PromptWrapper>
        <Prompt modelClient={mockModelClient} isNewPrompt />
      </PromptWrapper>,
    )

    await waitFor(() => {
      const button = screen.getByRole('button', {name: /gpt-4/i})
      expect(button).toBeInTheDocument()
    })
  })

  it('renders with no model if saved file do not contain model', () => {
    render(
      <PromptWrapper>
        <Prompt modelClient={mockModelClient} isNewPrompt={false} />
      </PromptWrapper>,
    )

    const button = screen.getByRole('button', {name: 'Select model'})
    expect(button).toBeInTheDocument()
  })

  test('Prefills the system prompt and parameters when the history state exists', async () => {
    jest.useFakeTimers()
    const currentTime = new Date('2025-01-01T00:00:00Z')
    jest.setSystemTime(currentTime)

    const model = mockModel()

    const state = {
      usr: {
        params: {max_token: 1234},
        model: model.original_name,
        systemPrompt: 'system prompt test',
      },
    }
    window.history.pushState(state, '', '/github-owner/github-repo/models/prompt/new')

    render(
      <PromptWrapper mockUpdatePrompt>
        <Prompt modelClient={mockModelClient} isNewPrompt />
      </PromptWrapper>,
    )

    expect(updatePrompt).toHaveBeenCalledWith({
      modelParameters: state.usr.params,
      model: state.usr.model,
      messages: [
        {message: state.usr.systemPrompt, role: 'system', timestamp: currentTime},
        {message: '', role: 'user', timestamp: currentTime},
      ],
    })
  })
})

const PromptWrapper = ({children, mockUpdatePrompt}: PropsWithChildren<{mockUpdatePrompt?: boolean}>) => {
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
        skippedRowIds: new Set<string>(),
        result: [],
        evaluators: [],
      },
    }),
  )

  const appPayload = getPromptAppPayload({payload: {promptPath: '/test-org/test-repo/prompts/new'}})

  const manager = useMemo(() => new PromptCompareManager(promptCompareDispatch), [promptCompareDispatch])
  if (mockUpdatePrompt) {
    manager.updatePrompt = updatePrompt
  }
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
