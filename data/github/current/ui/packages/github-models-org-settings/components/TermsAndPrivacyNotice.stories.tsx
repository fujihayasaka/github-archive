import type {Meta, StoryObj} from '@storybook/react'
import {TermsAndPrivacyNotice} from './TermsAndPrivacyNotice'

const meta = {
  title: 'Apps/GitHub Models org settings/TermsAndPrivacyNotice',
  component: TermsAndPrivacyNotice,
} satisfies Meta<typeof TermsAndPrivacyNotice>

export default meta

export const Example: StoryObj = {
  render: () => <TermsAndPrivacyNotice />,
}
