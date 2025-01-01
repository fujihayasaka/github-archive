import {VisualStudioUnmatchDialog} from './VisualStudioUnmatchDialog'
import type {Meta, StoryObj} from '@storybook/react'

const meta: Meta<typeof VisualStudioUnmatchDialog> = {
  title: 'Apps/Licensing/Enterprise Cloud/VisualStudioUnmatchDialog',
  component: VisualStudioUnmatchDialog,
}
export default meta

type Story = StoryObj<typeof VisualStudioUnmatchDialog>

export const Metered: Story = {
  render: function DefaultStory(args) {
    return <VisualStudioUnmatchDialog {...args} isVolumeLicensed={false} />
  },
}

export const Volume: Story = {
  render: function ExcludingPerSeatCostStory(args) {
    return <VisualStudioUnmatchDialog {...args} isVolumeLicensed />
  },
}

export const Error: Story = {
  render: function ErrorStory(args) {
    return <VisualStudioUnmatchDialog {...args} errorMessage="An error occurred" />
  },
}
