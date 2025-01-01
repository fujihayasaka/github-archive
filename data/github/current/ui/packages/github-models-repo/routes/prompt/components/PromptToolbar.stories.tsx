import {createRepository} from '@github-ui/current-repository/test-helpers'
import {repoModelPlaygroundPath} from '@github-ui/paths'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import type {Meta, StoryObj} from '@storybook/react'
import {fn} from '@storybook/test'
import {mockModel, mockTokenUsage} from '../../../test-utils/mock-data'
import {PromptToolbar} from './PromptToolbar'

const repo = createRepository()
const pathname = repoModelPlaygroundPath(repo, mockModel())

const meta = {
  title: 'Apps/GitHub Models repository/PromptToolbar',
  component: PromptToolbar,
  decorators: [storyWrapper({pathname})],
  args: {
    model: mockModel(),
    tokenUsage: mockTokenUsage({lastMessageOutputTokens: 1200, totalOutputTokens: 123456}),
    canRun: true,
    handleRun: fn(),
    handleStop: fn(),
  },
} satisfies Meta<typeof PromptToolbar>

export default meta

type Story = StoryObj<typeof PromptToolbar>

export const Example = {} satisfies Story
