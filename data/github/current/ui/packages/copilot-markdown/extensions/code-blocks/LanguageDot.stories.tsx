import {LanguageDot} from './LanguageDot'
import type {Meta, StoryFn} from '@storybook/react'

export default {
  title: 'Copilot/markdown/LanguageDot',
  component: LanguageDot,
  args: {
    color: 'red',
  },
  argTypes: {
    color: {control: 'color'},
  },
} satisfies Meta<typeof LanguageDot>

export const Default: StoryFn<typeof LanguageDot> = args => <LanguageDot {...args} />
Default.storyName = 'LanguageDot'
