import type {Meta} from '@storybook/react'
import {ExpandableContent, type ExpandableContentProps} from '../ExpandableContent'

const meta = {
  title: 'Apps/Code Quality/Expandable Content',
  component: ExpandableContent,
  parameters: {
    controls: {expanded: true, sort: 'alpha'},
  },
  argTypes: {},
} satisfies Meta<typeof ExpandableContent>

export default meta

const defaultArgs: Partial<ExpandableContentProps> = {
  collapsedContent: 'Why did Copilot refuse to write bad code?',
  expandedContent: (
    <div>
      Because it didn&apos;t want to get <em>deprecated</em>! Instead, it always aims to deliver production-ready
      punchlines—like this one. 😄
    </div>
  ),
}

export const Default = {
  args: defaultArgs,
  render: (args: ExpandableContentProps) => <ExpandableContent {...args} />,
}
