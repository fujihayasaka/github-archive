import type {Meta} from '@storybook/react'
import {ReposSelectPanelWrapper, type ReposSelectPanelWrapperProps} from './ReposSelectPanelWrapper'

const meta = {
  title: 'ReposComponents/SearchDropdown',
  component: ReposSelectPanelWrapper,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
} satisfies Meta<typeof ReposSelectPanelWrapper>

export default meta

const defaultArgs: Partial<ReposSelectPanelWrapperProps> = {
  title: 'TestLabel',
  items: [
    {text: 'Foo', id: 'foo'},
    {text: 'Bar', id: 'bar'},
  ],
  onSelect: () => {},
}

export const ReposSelectPanelWrapperWithSelection = {
  args: {
    ...defaultArgs,
    selectedItem: {text: 'Foo', id: 'foo'},
  },
  render: (args: ReposSelectPanelWrapperProps) => <ReposSelectPanelWrapper {...args} />,
}
