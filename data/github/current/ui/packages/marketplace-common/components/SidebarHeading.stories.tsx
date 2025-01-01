import type {Meta, StoryObj} from '@storybook/react'
import SidebarHeading, {type SidebarHeadingProps} from './SidebarHeading'

const meta = {
  title: 'SidebarHeading',
  component: SidebarHeading,
} satisfies Meta<typeof SidebarHeading>

export default meta

type Story = StoryObj<typeof SidebarHeading>

export const Example: Story = {
  args: {
    title: 'All apps',
    count: 5,
    link: '/marketplace?type=apps',
    htmlTag: 'h3',
  },
  render: (props: SidebarHeadingProps) => <SidebarHeading {...props} />,
}
