import type {Meta, StoryObj} from '@storybook/react'
import {EnterpriseServerSummary} from './EnterpriseServerSummary'
import {getEnterpriseServerSummaryProps} from '../test-utils/mock-data'

const meta = {
  title: 'Apps/Licensing/EnterpriseServerSummary',
  component: EnterpriseServerSummary,
  args: getEnterpriseServerSummaryProps(),
} satisfies Meta<typeof EnterpriseServerSummary>
export default meta
type Story = StoryObj<typeof EnterpriseServerSummary>

export const Default: Story = {
  name: 'Default',
  render: args => <EnterpriseServerSummary {...args} />,
}

export const Unbundled: Story = {
  parameters: {
    a11y: {
      test: 'todo',
    },
  },
  name: 'Unbundled',
  render: args => (
    <EnterpriseServerSummary {...args} codeSecurityLicenseCount={3} codeSecurityBillableLicenseCount={3} />
  ),
}
