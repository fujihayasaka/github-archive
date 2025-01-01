import {disableA11yRuleForDialog} from '@github-ui/react-core/test-utils'
import type {Meta} from '@storybook/react'
import {TemplateSelectionDialog, type TemplateSelectionDialogProps} from '../TemplateSelectionDialog'

const meta = {
  title: 'Apps/Security Campaigns/Template Selection Dialog',
  component: TemplateSelectionDialog,
  argTypes: {},
  parameters: {
    a11y: disableA11yRuleForDialog,
  },
} satisfies Meta<typeof TemplateSelectionDialog>

export default meta

const defaultArgs: Partial<TemplateSelectionDialogProps> = {
  templates: [
    {
      id: '1',
      name: 'Template 1',
      description: 'Description 1',
      href: '/href1',
      query: 'is:open',
    },
    {
      id: '2',
      name: 'Template 2',
      description: 'Description 2',
      href: '/href2',
      query: 'is:open',
    },
  ],
  organizationLogin: 'octodemo',
}

export const Default = {
  args: defaultArgs,
  render: (args: TemplateSelectionDialogProps) => <TemplateSelectionDialog {...args} />,
}
