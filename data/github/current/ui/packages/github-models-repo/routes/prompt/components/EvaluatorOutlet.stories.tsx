import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {mockModels} from '../../../test-utils/mock-data'
import {ModelsProvider} from '../contexts/ModelsContext'
import {initialPromptCompareState, PromptCompareStateProvider} from '../contexts/PromptCompareStateContext'
import {type PromptCompareManager, PromptCompareManagerContext} from '../prompt-compare-manager'
import type {CompareState} from '../prompt-compare-state'
import {EvaluatorOutlet} from './EvaluatorOutlet'

const manager = {} as PromptCompareManager
manager.evalsAddEvaluator = fn()

const state = initialPromptCompareState([], {
  compare: {
    evaluators: [
      {
        config: {
          name: 'eval 1',
        },
      },
      {
        config: {
          name: 'eval 2',
        },
      },
    ],
  } as CompareState,
})

const meta = {
  title: 'Apps/GitHub Models repository/EvaluatorOutlet',
  component: EvaluatorOutlet,
  decorators: [
    Story => (
      <ModelsProvider models={mockModels}>
        <PromptCompareStateProvider state={state}>
          <PromptCompareManagerContext.Provider value={manager}>
            <Story />
          </PromptCompareManagerContext.Provider>
        </PromptCompareStateProvider>
      </ModelsProvider>
    ),
  ],
} satisfies Meta<typeof EvaluatorOutlet>

export default meta

type Story = StoryObj<typeof EvaluatorOutlet>

export const Example = {} satisfies Story
