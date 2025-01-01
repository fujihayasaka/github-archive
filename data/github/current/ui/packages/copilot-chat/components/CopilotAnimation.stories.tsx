import type {Meta, StoryObj} from '@storybook/react'

import CopilotAnimation from './CopilotAnimation'

const meta = {
  title: 'Apps/Copilot/CopilotAnimation',
  component: CopilotAnimation,
  parameters: {},
  argTypes: {
    animationType: {
      options: [
        'affirmative',
        'celebrate',
        'tickle',
        'jumpWiggle',
        'confirm',
        'idle',
        'negative',
        'static',
        'thinking',
        'userInput',
        'activate',
      ],
      control: {type: 'select'},
    },
    mode: {
      options: ['immersive', 'assistive'],
      control: {type: 'select'},
    },
  },
} satisfies Meta<typeof CopilotAnimation>

export default meta

export const Default: StoryObj<typeof meta> = {
  args: {
    animationType: 'affirmative',
    mode: 'immersive',
    loopAnimation: true,
  },
  render: props => {
    return (
      <CopilotAnimation animationType={props.animationType} loopAnimation={props.loopAnimation} mode={props.mode} />
    )
  },
}
