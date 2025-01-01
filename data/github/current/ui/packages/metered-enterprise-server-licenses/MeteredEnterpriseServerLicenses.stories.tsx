import type {Meta, StoryObj} from '@storybook/react'
import {MeteredEnterpriseServerLicenses} from './MeteredEnterpriseServerLicenses'
import {getMeteredEnterpriseServerLicensesProps} from './test-utils/mock-data'

const meta = {
  title: 'Apps/Licensing/MeteredEnterpriseServerLicenses',
  component: MeteredEnterpriseServerLicenses,
  args: getMeteredEnterpriseServerLicensesProps(),
} satisfies Meta<typeof MeteredEnterpriseServerLicenses>

export default meta

type Story = StoryObj<typeof MeteredEnterpriseServerLicenses>

export const Default: Story = {
  name: 'Default',
  render: args => <MeteredEnterpriseServerLicenses {...args} />,
}

export const WithBundleMismatchWarning: Story = {
  name: 'With Bundle Mismatch Warning',
  render: args => (
    <MeteredEnterpriseServerLicenses {...args} enableGhasBundleMismatchWarning consumedEnterpriseLicenses={75} />
  ),
}
