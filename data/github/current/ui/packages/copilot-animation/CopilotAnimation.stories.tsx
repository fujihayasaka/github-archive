import type {Meta, StoryObj, StoryFn} from '@storybook/react'
import {fn} from '@storybook/test'

import {CopilotAnimation} from './CopilotAnimation'

import {Stack} from '@primer/react'

const meta = {
  title: 'Recipes/Copilot/CopilotAnimation',
  component: CopilotAnimation,
  parameters: {},
  argTypes: {
    animationType: {
      options: [
        'activate',
        'affirmative',
        'celebrate',
        'confirm',
        'idle',
        'jumpWiggle',
        'negative',
        'static',
        'thinking',
        'tickle',
        'userInput',
      ],
      control: {type: 'select'},
    },
    size: {
      options: [16, 24, 32, 48, 64, 96, 128],
      control: {type: 'select'},
    },
    className: {
      control: false,
    },
    style: {
      control: false,
    },
  },
  args: {
    animationType: 'activate',
    loopAnimation: true,
    size: 32,
    onAnimationEnd: fn(),
  },
} satisfies Meta<typeof CopilotAnimation>

export default meta

export const Default: StoryFn<typeof CopilotAnimation> = props => <CopilotAnimation {...props} />

export const AllAnimations: StoryObj<typeof meta> = {
  args: {
    animationType: 'activate',
    loopAnimation: true,
    size: 32,
  },
  argTypes: {
    ...meta.argTypes,
    animationType: {
      control: false,
    },
  },
  render: props => {
    return (
      <Stack direction="horizontal">
        <CopilotAnimation {...props} animationType="affirmative" />
        <CopilotAnimation {...props} animationType="celebrate" />
        <CopilotAnimation {...props} animationType="tickle" />
        <CopilotAnimation {...props} animationType="jumpWiggle" />
        <CopilotAnimation {...props} animationType="confirm" />
        <CopilotAnimation {...props} animationType="idle" />
        <CopilotAnimation {...props} animationType="negative" />
        <CopilotAnimation {...props} animationType="static" />
        <CopilotAnimation {...props} animationType="thinking" />
        <CopilotAnimation {...props} animationType="userInput" />
        <CopilotAnimation {...props} animationType="activate" />
      </Stack>
    )
  },
}
