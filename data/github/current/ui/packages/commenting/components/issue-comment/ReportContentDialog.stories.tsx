// eslint-disable-next-line no-restricted-imports
import ToastContext, {useToastContext} from '@github-ui/toast/ToastContext'
import type {Meta, StoryObj} from '@storybook/react'
import {RelayEnvironmentProvider} from 'react-relay'
import {createMockEnvironment} from 'relay-test-utils'

import {ReportContentDialog} from './ReportContentDialog'

// Create a mock Relay environment
const mockEnvironment = createMockEnvironment()

// Relay environment and Toast provider wrapper
const WithProviders = ({children}: {children: React.ReactNode}) => {
  const toastContext = useToastContext()

  return (
    <RelayEnvironmentProvider environment={mockEnvironment}>
      <ToastContext.Provider value={toastContext}>{children}</ToastContext.Provider>
    </RelayEnvironmentProvider>
  )
}

const meta = {
  title: 'Commenting/ReportContentDialog',
  component: ReportContentDialog,
  parameters: {
    controls: {expanded: true},
    a11y: {
      config: {
        // Following a11y guidance from github/accessibility
        rules: [
          {id: 'color-contrast', enabled: true},
          {id: 'aria-dialog', enabled: true},
          {id: 'focus-trap-dialog', enabled: true},
          {id: 'role-dialog-name', enabled: true},
        ],
      },
    },
    layout: 'centered',
  },
  tags: ['autodocs'],
  argTypes: {
    onClose: {action: 'onClose'},
    contentType: {
      control: 'select',
      options: ['issue', 'comment', 'pull request', 'content'],
      description: 'Type of content being reported',
    },
  },
  decorators: [
    Story => (
      <WithProviders>
        <Story />
      </WithProviders>
    ),
  ],
} satisfies Meta<typeof ReportContentDialog>

export default meta
type Story = StoryObj<typeof meta>

// Default props for all stories
const defaultProps = {
  owner: 'github',
  ownerUrl: 'https://github.com/github',
  contentId: 'MDExOlB1bGxSZXF1ZXN0NTg4Mzgy',
  reportUrl: 'https://github.com/contact/report-abuse',
  onClose: () => {},
  contentType: 'comment' as const,
}

export const Default: Story = {
  args: defaultProps,
}
