import type {Meta, StoryObj} from '@storybook/react'
import {CreatePromptFileButton} from './CreatePromptFileButton'
import {parametersConfig} from '../../../utils/story-utils'
import {storyWrapper} from '@github-ui/react-core/test-utils'
import {mockShowModelPayload} from '../../show/components/__tests__/mocks'
import {mockModelState} from './__tests__/mocks'

type StoryArgs = typeof CreatePromptFileButton

const meta = {
  title: 'Apps/GitHub Models/CreatePromptFileButton',
  component: CreatePromptFileButton,
  args: {
    modelState: mockModelState(),
    repository: {
      name: 'repo-name',
      ownerLogin: 'owner-login',
    },
  },
  parameters: parametersConfig,
  decorators: [
    storyWrapper({
      routePayload: mockShowModelPayload(),
    }),
  ],
} satisfies Meta<StoryArgs>

export default meta

type Story = StoryObj<StoryArgs>

export const Example = {} satisfies Story
