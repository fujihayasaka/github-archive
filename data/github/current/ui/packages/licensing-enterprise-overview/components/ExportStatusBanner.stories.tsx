import type {Meta, StoryObj} from '@storybook/react'
import {ExportStatusBanner} from './ExportStatusBanner'
import {ExportJobState} from '../types/export-job-state'

const meta = {
  title: 'Apps/LicensingEnterpriseOverview/ExportStatusBanner',
  component: ExportStatusBanner,
  args: {
    onDismissClick: () => {},
    onDownloadButtonClick: () => {},
  },
} satisfies Meta<typeof ExportStatusBanner>

export default meta

type Story = StoryObj<typeof ExportStatusBanner>

export const Error: Story = {
  name: 'Error',
  render: args => <ExportStatusBanner {...args} exportJobState={ExportJobState.Error} />,
}

export const Pending: Story = {
  name: 'Pending',
  render: args => <ExportStatusBanner {...args} exportJobState={ExportJobState.Pending} />,
}

export const PendingWithEmailNotification: Story = {
  name: 'Pending with email notification',
  render: args => (
    <ExportStatusBanner
      {...args}
      exportJobState={ExportJobState.Pending}
      emailNotificationMessage="The CSV report is being generated. You'll receive an email at foo@example.com as soon as it's ready."
    />
  ),
}

export const Ready: Story = {
  name: 'Ready',
  render: args => <ExportStatusBanner {...args} exportJobState={ExportJobState.Ready} />,
}

export const ReadyWithDownloadButton: Story = {
  name: 'Ready with download button',
  render: args => <ExportStatusBanner {...args} exportJobState={ExportJobState.Ready} showDownloadButtonOnReady />,
}
