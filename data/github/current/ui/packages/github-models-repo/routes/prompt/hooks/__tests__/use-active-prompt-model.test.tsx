// eslint-disable-next-line @github-ui/github-monorepo/filename-convention
import {CurrentRepositoryProvider} from '@github-ui/current-repository'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {AppPayloadContext} from '@github-ui/react-core/use-app-payload'
import {renderHook} from '@testing-library/react'
import {type PropsWithChildren, useMemo, useReducer} from 'react'
import {getPromptAppPayload, mockModel} from '../../../../test-utils/mock-data'
import {ModelsProvider} from '../../contexts/ModelsContext'
import {initialPromptCompareState, PromptCompareStateProvider} from '../../contexts/PromptCompareStateContext'
import {PromptCompareManager, PromptCompareManagerContext, promptCompareReducer} from '../../prompt-compare-manager'
import type {PromptConfig} from '../../prompts'
import useActivePromptModel from '../use-active-prompt-model'

describe('useActivePromptModel', () => {
  it('returns the first prompt in list of prompts', () => {
    const {result} = renderHook(() => useActivePromptModel(), {
      wrapper: ({children}) => (
        <PromptWrapper mockPrompts={[{name: 'Test Prompt', messages: [], model: 'gpt-4o'}]}>{children}</PromptWrapper>
      ),
    })

    expect(result.current!.id).toStrictEqual('gpt-4o')
  })

  it('returns undefined if no model is selected', () => {
    const {result} = renderHook(() => useActivePromptModel(), {
      wrapper: ({children}) => (
        <PromptWrapper mockPrompts={[{name: 'Test prompt', messages: []}]}>{children}</PromptWrapper>
      ),
    })

    expect(result.current).toBeUndefined()
  })
})

const PromptWrapper = ({children, mockPrompts}: PropsWithChildren<{mockPrompts?: PromptConfig[]}>) => {
  const repository = createRepository()

  const availableModels = [
    mockModel({id: 'gpt-4o', name: 'gpt-4o', friendly_name: 'gpt-4o', original_name: 'gpt-4o'}),
    mockModel(),
  ]
  const prompts = mockPrompts || [
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
