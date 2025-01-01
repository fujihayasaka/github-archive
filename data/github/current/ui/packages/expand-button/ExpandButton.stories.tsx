import type {Meta} from '@storybook/react'
import {ExpandButton, type ExpandButtonProps} from './ExpandButton'

const meta = {
  title: 'Recipes/ExpandButton',
  component: ExpandButton,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {
    expanded: {control: 'boolean', defaultValue: false},
  },
} satisfies Meta<typeof ExpandButton>

export default meta

const defaultArgs: Partial<ExpandButtonProps> = {
  expanded: false,
  onToggleExpanded: () => {},
  testid: 'expand-button-test',
  alignment: 'left',
  ariaLabel: 'Expand it!',
}

export const ExpandButtonExample = {
  args: {
    ...defaultArgs,
  },
  render: (args: ExpandButtonProps) => <ExpandButton {...args} />,
}
