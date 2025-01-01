import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {type PromptCompareManager, PromptCompareManagerContext} from '../../prompt-compare-manager'
import {EvaluatorTemplates} from '../../evaluators'
import {EvaluatorDialog} from './EvaluatorDialog'

const template = EvaluatorTemplates[0]

const manager = {} as PromptCompareManager
manager.evalsUpdateEvaluator = fn()
manager.evalsAddEvaluator = fn()

const meta = {
  title: 'Apps/GitHub Models repository/EvaluatorDialog',
  component: EvaluatorDialog,
  args: {
    template,
    evaluatorIndex: 0,
    evaluator: template?.configTemplate,
  },
  decorators: [
    Story => (
      <PromptCompareManagerContext.Provider value={manager}>
        <Story />
      </PromptCompareManagerContext.Provider>
    ),
  ],
} satisfies Meta<typeof EvaluatorDialog>

export default meta

type Story = StoryObj<typeof EvaluatorDialog>

export const Example = {} satisfies Story
