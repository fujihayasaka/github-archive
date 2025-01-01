import type {Meta} from '@storybook/react'
import {RegexPatternInput, type RegexPatternInputProps} from './RegexPatternInput'

const meta = {
  title: 'Recipes/RegexTesterDialog/RegexPatternInput',
  component: RegexPatternInput,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof RegexPatternInput>

export default meta

const defaultArgs: Partial<RegexPatternInputProps> = {
  onChange: () => null,
  value: '*abc',
  validationError: 'Invalid pattern',
}

export const RegexTesterDialogExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: RegexPatternInputProps) => <RegexPatternInput {...args} />,
}
