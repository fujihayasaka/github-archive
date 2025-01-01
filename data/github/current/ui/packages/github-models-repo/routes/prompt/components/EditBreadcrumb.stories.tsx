import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {type PromptCompareManager, PromptCompareManagerContext} from '../prompt-compare-manager'
import {createRepository} from '@github-ui/current-repository/test-helpers'
import {EditBreadcrumb} from './EditBreadcrumb'

const manager = {} as PromptCompareManager
manager.updatePromptPath = fn()

const meta = {
  title: 'Apps/GitHub Models repository/EditBreadcrumb',
  component: EditBreadcrumb,
  args: {
    folderPath: 'fancy_prompts/tmp/v2',
    fileName: 'my.prompt.yml',
    repository: createRepository(),
  },
  decorators: [
    Story => (
      <PromptCompareManagerContext.Provider value={manager}>
        <Story />
      </PromptCompareManagerContext.Provider>
    ),
  ],
} satisfies Meta<typeof EditBreadcrumb>

export default meta

type Story = StoryObj<typeof EditBreadcrumb>

export const Example = {} satisfies Story
