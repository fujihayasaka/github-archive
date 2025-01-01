import type {Meta, StoryObj} from '@storybook/react'

import {CodeInsightsDialog, type CodeInsightsDialogProps} from './CodeInsightsDialog'

const meta = {
  title: 'Apps/Copilot/CodeInsightsDialog',
  component: CodeInsightsDialog,
  parameters: {},
  argTypes: {},
} satisfies Meta<typeof CodeInsightsDialog>

export default meta

const defaultArgs: CodeInsightsDialogProps = {
  onClose: () => {},
  codeVulnerabilities: [
    {
      startOffset: 0,
      endOffset: 0,
      details: {
        description: 'Sample Vulnerability',
        type: 'Security',
        uiDescription: 'Sample UI Description',
        uiType: 'Sample UI Type',
      },
    },
  ],
  publicCodeReferences: [
    {
      startOffset: 0,
      endOffset: 0,
      details: {
        sourceURL: 'https://github.com/github/github/blob/main/LICENSE',
        license: 'MIT',
        language: 'JavaScript',
      },
    },
  ],
}

export const Default: StoryObj<CodeInsightsDialogProps> = {
  args: {
    ...defaultArgs,
  },
  render: args => <CodeInsightsDialog {...args} />,
}
